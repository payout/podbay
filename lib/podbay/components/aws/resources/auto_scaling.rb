module Podbay
  module Components
    module Aws::Resources
      class AutoScaling < Base
        autoload(:Waiter, 'podbay/components/aws/resources/auto_scaling/waiter')

        def launch_config_exists?(name)
          !!launch_configuration(name).data
        end

        def group_of_instance(instance_id)
          instance = instances(instance_ids: [instance_id]).to_a.first
          instance && instance.group_name
        end

        def set_group_size(group, size)
          if size.is_a?(Fixnum)
            params = { min_size: size, max_size: size, desired_capacity: size }
          elsif size.is_a?(Hash)
            params = {}.tap do |h|
              [:min_size, :max_size, :desired_capacity].each do |key|
                h[key] = size[key] if size[key]
              end
            end
          end

          group.update(params)
          if params.has_key?(:desired_capacity)
            Waiter.wait_until_group_has_size(group, params[:desired_capacity])
            Waiter.wait_until_no_scaling_activities(group)
            Waiter.wait_until_all_instances_running(group)
          end
        end

        def copy_launch_config(launch_config, updated_params)
          launch_config_params = launch_config.data.to_h
          new_params = launch_config_params.merge(updated_params)
            .reject do |k, v|
              [:launch_configuration_arn, :created_time, :block_device_mappings]
                .include?(k) || v == ''
            end

          create_launch_configuration(new_params)
        end

        def copy_group(group, updated_params)
          new_params = group.data.to_h.merge(updated_params)
            .reject do |k, _|
              [:auto_scaling_group_arn, :instances, :created_time,
                :suspended_processes, :enabled_metrics, :status].include?(k)
            end

          new_params[:tags].each { |t| t.reject! { |k,_| k == :resource_id } }

          create_group(new_params).tap do |g|
            g.wait_until_exists { |w| w.before_wait { print '.' } }
          end
        end

        def step_deploy(new_group, old_group, target_size)
          # Refresh group objects since they might be stale
          new_group = group(new_group.name)
          old_group = group(old_group.name)

          orig_params = old_group.data.to_h
          elbs = old_group.load_balancer_names
          role = role_of(old_group)

          # Allow list of services to be changed between deployments.
          srvcs = services_of(new_group)

          new_group_size = new_group.instances.to_a.length
          new_i_ids = []

          ldr_idxs = leader_sync_indexes if role == 'server'

          until (target_size == new_group_size) && old_group.instances.empty?
            begin
              if new_group_size < target_size
                _step_deploy_set(new_group, new_group_size += 1)

                new_group = group(new_group.name)
                i_id = (new_group.instances.map(&:id) - new_i_ids).first
                new_i_ids << i_id if i_id

                puts 'Performing health check on new instance... '
                _step_health_check(new_i_ids.last, srvcs, elbs, role, ldr_idxs)
              end

              _step_deploy_decrement(old_group)
              old_group = group(old_group.name)
            rescue StandardError => e
              step_deploy_failure(e, new_group, old_group, orig_params)

              # Need to retry the last iteration.
              new_group_size -= 1
            rescue Interrupt
              # Rollback
              step_deploy(old_group, new_group, orig_params[:desired_capacity])
              raise
            end
          end

          _delete_group_and_launch_config(old_group)
        end

        def teardown_group(group, delete_elbs = true)
          launch_config = group.launch_configuration

          group.update(min_size: 0)
          _teardown_group_instances(group.instances)

          # Even with torn down instances, the ASG takes time to update
          Waiter.wait_until_group_has_size(group, 0)

          # Destroy all (if any) ELBs attached to the ASG
          if delete_elbs
            group.load_balancers.each do |elb|
              print 'Tearing down ELB... '
              Aws::Resources::ELB.delete_load_balancer(
                load_balancer_name: elb.name
              )
              puts 'Complete!'.green
            end
          end

          Waiter.wait_until_no_scaling_activities(group)
          delete_group(group)

          print 'Tearing down launch configuration... '
          launch_config.delete
          puts 'Complete!'.green
        end

        def delete_group(group)
          print 'Deleting AutoScaling Group...'
          group.delete
          group.wait_until_not_exists { |w| w.before_wait { print '.' } }
          puts 'Complete!'.green
        end

        def role_of(group)
          role_tag = group.data.tags.find { |t| t.key == 'podbay:role' }
          role_tag && role_tag.value
        end

        def services_of(group)
          services_tag = group.data.tags.find do |t|
            t.key == 'podbay:modules:static_services'
          end

          ((services_tag && services_tag.value) || '').split(',')
        end

        ##
        # Checks if the server is synced with its leader. If it can't connect
        # to the server, it prompts the user to check manually
        #
        # Params:
        # - +ip+ -> ip address of the server to check
        # - +ldr_c_idx+ -> leader's commit index
        # - +ldr_ll_idx+ -> leader's last log index
        # - +iters+ -> number of times to attempt checking the server
        # - +delay+ -> number of seconds to wait before checking the server
        #
        # Returns:
        # - Returns true if the server is synced. Otherwise, returns false.
        def server_synced?(ip, ldr_c_idx, ldr_ll_idx, iters = 50, delay = 5)
          print 'Waiting for new Consul server to sync data from the leader... '

          iters.times do
            unless (server_info = _get_podbay_info(ip, 'consul_info'))
              return _prompt_manual_server_check(ip, ldr_c_idx, ldr_ll_idx)
            end
            server_c_idx = server_info[:raft][:commit_index]
            server_ll_idx = server_info[:raft][:last_log_index]

            if ldr_c_idx <= server_c_idx && ldr_ll_idx <= server_ll_idx
              puts ' new Consul Server synced!'.green
              return true
            end

            sleep(delay).tap { print '.' }
          end

          false
        end

        def leader_sync_indexes
          ldr_info = _get_podbay_info(Podbay::Consul.leader_ip, 'consul_info')
          if ldr_info
            c_idx = ldr_info[:raft][:commit_index]
            ll_idx = ldr_info[:raft][:last_log_index]
          else
            c_idx, ll_idx = _prompt_manual_leader_check
          end

          { commit_index: c_idx, last_log_index: ll_idx }
        end

        def step_deploy_failure(error, new_group, old_group, orig_params)
          puts "Encountered failure state: #{error.message.inspect}".red
          if _prompt_retry_or_rollback == :rollback
            step_deploy(old_group, new_group, orig_params[:desired_capacity])
            raise error
          else
            print 'Retrying Step Deployment...'.yellow
          end
        end

        private

        def _step_deploy_set(group, size)
          unless group.instances.to_a.size == size
            print "▲ Scaling up new group to #{size}..."
          end

          set_group_size(group, size)
          puts ' Complete!'.green
        end

        def _step_deploy_decrement(old_group)
          old_group = group(old_group.name)
          return if old_group.desired_capacity == 0
          old_group_size = old_group.desired_capacity - 1
          print "▼ Scaling down old group to #{old_group_size}..."
          set_group_size(old_group, old_group_size)
          puts ' Complete!'.green
        end

        def _step_health_check(i_id, services, elbs, role, leader_idxs = nil)
          unless EC2.instance_healthy?(i_id, services, elbs)
            fail UnhealthyDeploymentError, 'New group encountered unhealthy ' \
              'state during scaling up'
          end

          if role == 'server'
            is_synced = server_synced?(EC2.private_ip(i_id),
              leader_idxs[:commit_index], leader_idxs[:last_log_index])

            unless is_synced
              fail ConsulServerNotSyncedError, 'New Consul server is not synced'
            end
          end
        end

        def _prompt_manual_leader_check
          puts '*Manual input required*'.yellow
          puts "Run `consul info` on the leader: #{Podbay::Consul.leader_ip} "
          selection = nil

          ['commit_index', 'last_log_index'].map do |idx|
            loop do
              print "Enter the leader's '#{idx}': "
              break if (selection = $stdin.gets.chomp) =~ /\A\d+\z/
              puts "\nValue must be an integer".red
            end

            selection.to_i
          end
        end

        def _prompt_manual_server_check(server_ip, ldr_c_idx, leader_ll_idx)
          puts "\nCannot connect to Consul server. Manual input required " \
            "(run `consul info` on the server: #{server_ip.inspect}):".yellow
          puts "Ensure that the server has >= the leader's commit_index: " \
            "#{ldr_c_idx} and last_log_index: #{leader_ll_idx}"

          Utils.prompt_question('Has server synced with leader?')
        end

        def _delete_group_and_launch_config(group, max_attempts = 3)
          old_launch_config = group.launch_configuration

          delete_attempts = 1
          puts 'Deleting old group... '
          loop do
            # Attempt to delete the old asg + launch config. Retry max_attempts
            # times just in case.
            begin
              group = group(group.name)
              delete_group(group)
              old_launch_config.delete
              puts 'Complete!'.green
              break
            rescue StandardError, Interrupt
              if delete_attempts == max_attempts
                puts "Unable to delete ASG: #{group.name.inspect}".red
                raise
              end

              delete_attempts += 1
              puts "Deletion unsuccessful. Attempt #{delete_attempts} of 3".red
              sleep(5)
            end
          end
        end

        def _teardown_group_instances(group_instances)
          # `instance` and `ec2_instance` refer to the same instance. We need
          # `ec2_instance` since waiting is only available through that
          # interface. And we need `instance` so we can terminate while
          # decrementing its autoscaling group's desired capacity.
          group_instances.each do |instance|
            ec2_instance = Aws::Resources::EC2.instance(instance.id)
            instance_state = ec2_instance.state.name

            next if ['terminating', 'terminated'].include?(instance_state)

            # If a teardown is happening while an instance is in a pending
            # state, we need to wait until it's running before tearing it down
            if instance_state == 'pending'
              print "Instance #{ec2_instance.id} is not in running state yet." \
                " Waiting..."
              ec2_instance.wait_until_running do |w|
                w.before_wait { print '.' }
              end
              puts ' Done! Continuing with teardown...'.green
            end

            loop do
              begin
                instance.terminate(should_decrement_desired_capacity: true)
                break
              rescue ::Aws::AutoScaling::Errors::ScalingActivityInProgress
                print '.'
                sleep(1)
              end
            end
          end

          group_instances.each do |i|
            print "Tearing down instance #{i.id}..."
            Aws::Resources::EC2.instance(i.id).wait_until_terminated do |waiter|
              waiter.before_wait { |_,_| print '.' }
            end
            puts ' Complete!'.green
          end
        end

        def _prompt_retry_or_rollback
          Utils.prompt_choice('Select action from below:', :retry, :rollback)
        end

        def _get_podbay_info(ip_address, path)
          attempts = 0
          begin
            Utils.podbay_info(ip_address, path)
          rescue StandardError => e
            attempts += 1
            puts "Error retrieving server info: #{e.class.name}"
            puts "Retry #{attempts} of 3"

            retry if attempts < 3
          end
        end
      end # AutoScaling
    end # Aws::Resources
  end # Components
end # Podbay
