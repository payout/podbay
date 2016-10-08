module Podbay
  module Components
    module Aws::Resources
      RSpec.describe AutoScaling do
        let(:asg) { AutoScaling.new }

        describe '#client' do
          subject { asg.client }

          it { is_expected.to be_a ::Aws::AutoScaling::Client }
        end # #client

        describe '#launch_config_exists?' do
          subject { asg.launch_config_exists?('name') }

          before do
            allow(asg).to receive(:launch_configuration)
              .and_return(launch_config)
          end

          let(:launch_config) { double('Launch Config', data: data) }
          let(:data) { { some_data: 'value' } }

          it { is_expected.to eq true }

          context 'with missing launch config' do
            let(:data) { nil }
            let(:sg) { double('VPC', id: 'sg-01234567') }

            it { is_expected.to eq false }
          end # with invalid vpc id
        end # #launch_config_exists

        describe '#group_of_instance' do
          subject { asg.group_of_instance(instance_id) }

          let(:instance_id) { 'i-abc1234' }

          before do
            allow(asg).to receive(:instances).with(instance_ids: [instance_id])
              .and_return(instances)
          end

          let(:instances) { [] }

          context 'with instance found' do
            let(:instances) { [double('instance', group_name: group_name)] }
            let(:group_name) { 'gr-abc1234' }

            it { is_expected.to eq group_name }
          end

          context 'with instance not found' do
            let(:instances) { [] }
            it { is_expected.to be nil }
          end
        end # #group_of_instance

        describe '#set_group_size' do
          subject { asg.set_group_size(group, size) }

          let(:waiter_mock) { double('Waiter') }
          let(:group) { double('group') }
          let(:size) { 1 }

          around do |ex|
            Aws::Resources::AutoScaling::Waiter.mock(waiter_mock) do
              ex.run
            end
          end

          after { subject }

          before do
            allow(group).to receive(:update)
            allow(waiter_mock).to receive(:wait_until_no_scaling_activities)
            allow(waiter_mock).to receive(:wait_until_group_has_size)
            allow(waiter_mock).to receive(:wait_until_all_instances_running)
          end

          context 'with integer size' do
            context 'with size = 1' do
              it 'should set up the correct params' do
                expect(group).to receive(:update).with(
                  min_size: 1,
                  max_size: 1,
                  desired_capacity: 1
                )
              end

              it 'should wait for the scaling activities' do
                expect(waiter_mock).to receive(:wait_until_no_scaling_activities)
                  .with(group)
              end

              it 'should wait for the group has the specified size' do
                expect(waiter_mock).to receive(:wait_until_group_has_size).with(
                  group, 1
                )
              end
            end # with size = 1
          end # with integer size

          context 'with hash size' do
            context 'with desired_capacity set' do
              let(:size) { { desired_capacity: 2 } }

              it 'should set up the correct params' do
                expect(group).to receive(:update).with(desired_capacity: 2)
              end

              it 'should wait for the scaling activities' do
                expect(waiter_mock).to receive(:wait_until_no_scaling_activities)
                  .with(group)
              end

              it 'should wait for the group has the specified size' do
                expect(waiter_mock).to receive(:wait_until_group_has_size).with(
                  group, 2
                )
              end
            end # with desired capacity set

            context 'with min_size and max_size set' do
              let(:size) { { min_size: 2, max_size: 2 } }

              it 'should set up the correct params' do
                expect(group).to receive(:update).with(
                  min_size: 2, max_size: 2
                )
              end

              it 'should not wait for the scaling activities' do
                expect(waiter_mock).not_to receive(:wait_until_no_scaling_activities)
              end

              it 'should not wait for the group has the specified size' do
                expect(waiter_mock).not_to receive(:wait_until_group_has_size)
              end
            end # with min_size and max_size set

            context 'with all params set' do
              let(:size) { { desired_capacity: 2, min_size: 1, max_size: 3 } }

              it 'should set up the correct params' do
                expect(group).to receive(:update).with(
                  min_size: 1,
                  desired_capacity: 2,
                  max_size: 3
                )
              end

              it 'should wait for the scaling activities' do
                expect(waiter_mock).to receive(:wait_until_no_scaling_activities)
                  .with(group)
              end

              it 'should wait for the group has the specified size' do
                expect(waiter_mock).to receive(:wait_until_group_has_size).with(
                  group, 2
                )
              end
            end # with all params set
          end # with hash size
        end # #set_group_size

        describe '#copy_launch_config' do
          subject { asg.copy_launch_config(params, updated_params) }

          let(:params) do
            Struct.new(:data).new(
              launch_configuration_arn: 'abc123',
              created_time: '10-10-2016',
              associate_pubilc_ip_address: 'true',
              block_device_mappings: []
            )
          end
          let(:updated_params) do
            {
              image_id: 'ami-abc1234'
            }
          end

          after { subject }

          it 'should reject invalid fields' do
            expect(asg).to receive(:create_launch_configuration).with(
              associate_pubilc_ip_address: 'true',
              image_id: 'ami-abc1234'
            )
          end
        end # #copy_launch_config

        describe '#copy_group' do
          subject { asg.copy_group(params, updated_params) }

          let(:params) do
            Struct.new(:data).new(
              auto_scaling_group_arn: 'test',
              instances: 'test',
              created_time: 'test',
              suspended_processes: 'test',
              enabled_metrics: 'test',
              status: 'test',
              created_time: '10-10-2016',
              tags: [
                {
                  :resource_id=>"gr-abc1234",
                  :resource_type=>"auto-scaling-group",
                  :key=>"podbay:cluster",
                  :value=>"podbay-test-cluster",
                  :propagate_at_launch=>true
                },
                {
                  :resource_id=>"gr-abc1234",
                  :resource_type=>"auto-scaling-group",
                  :key=>"podbay:role",
                  :value=>"client",
                  :propagate_at_launch=>true
                }
              ]
            )
          end
          let(:updated_params) do
            {
              min_size: 2,
              max_size: 2,
              desired_capacity: 2
            }
          end
          let(:group) { double('group') }

          before do
            allow(asg).to receive(:create_group).and_return(group)
            allow(group).to receive(:wait_until_exists)
          end

          after { subject }

          it 'should reject invalid fields' do
            expect(asg).to receive(:create_group).with(
              min_size: 2,
              max_size: 2,
              desired_capacity: 2,
              tags: [
                {
                  :resource_type=>"auto-scaling-group",
                  :key=>"podbay:cluster",
                  :value=>"podbay-test-cluster",
                  :propagate_at_launch=>true
                },
                {
                  :resource_type=>"auto-scaling-group",
                  :key=>"podbay:role",
                  :value=>"client",
                  :propagate_at_launch=>true
                }
              ]
            )
          end

          it 'should wait until the group exists' do
            expect(group).to receive(:wait_until_exists)
          end
        end # #copy_group

        describe '#step_deploy', :step_deploy do
          subject { asg.step_deploy(new_group, old_group, target_size) }

          # Old group vars
          let(:old_group) { double('old_group', name: 'old_group') }
          let(:old_group_orig_size) { target_size }
          let(:old_group_params) do
            {
              min_size: old_group_orig_size,
              max_size: old_group_orig_size,
              desired_capacity: old_group_orig_size
            }
          end
          let(:old_launch_config) { double('old_launch_config') }
          let(:old_group_instances) { target_size.times.map { double('instance') } }

          # New group vars
          let(:new_group) { double('new_group', name: 'new_group') }
          let(:new_group_instances) { [] }
          let(:new_instance_ids) do
            target_size.times.each_with_index.map { |i| "abc-123#{i}" }
          end

          let(:target_size) { 0 }
          let(:role) { 'client' }
          let(:services) { ['service-name'] }
          let(:elb_names) { [] }
          let(:instance_healthy) { [true] }
          let(:scale_up_error) { nil }
          let(:scale_down_error) { nil }

          let(:consul_mock) { double('Podbay::Consul') }
          let(:ec2_mock) { double('Resources::EC2') }
          let(:elb_mock) { double('Resources::ELB') }

          around do |ex|
            Podbay::Consul.mock(consul_mock) do
              Aws::Resources::EC2.mock(ec2_mock) do
                ex.run
              end
            end
          end

          before do
            # Simulate scaling up / scaling down the groups
            error_raised = false
            allow(asg).to receive(:set_group_size) do |g, s|
              if s > g.instances.length
                # Simulate error if needed by a test
                if scale_up_error && !error_raised
                  error_raised = true
                  fail scale_up_error
                end

                until g.instances.length == s
                  g.instances.push(
                    double(id: new_instance_ids[g.instances.length])
                  )
                end
              elsif s < g.instances.length
                # Simulate error if needed by a test
                if scale_down_error && !error_raised
                  error_raised = true
                  fail scale_down_error
                end

                g.instances.shift(g.instances.length - s)
              end
            end

            # Old group methods
            allow(old_group).to receive(:data).and_return(old_group_params)
            allow(old_group).to receive(:load_balancer_names)
              .and_return(elb_names)
            allow(asg).to receive(:group).with(old_group.name)
              .and_return(old_group)
            allow(old_group).to receive(:launch_configuration)
              .and_return(old_launch_config)
            allow(old_group).to receive(:delete)
            allow(old_launch_config).to receive(:delete)
            allow(old_group).to receive(:wait_until_not_exists)
            allow(old_group).to receive(:instances) { old_group_instances }
            allow(old_group).to receive(:desired_capacity) do
              old_group_instances.length
            end

            # New group methods
            allow(asg).to receive(:group).with(new_group.name)
              .and_return(new_group)
            allow(new_group).to receive(:instances)
              .and_return(new_group_instances)

            allow(ec2_mock).to receive(:instance_healthy?)
              .and_return(*instance_healthy)
            allow(asg).to receive(:role_of).and_return(role)
            allow(asg).to receive(:services_of).and_return(services)
          end

          context 'with role=client' do
            let(:role) { 'client' }

            context 'with instance healthy' do
              let(:instance_healthy) { [true] }

              after { subject }

              context 'with target_size = 0' do
                let(:target_size) { 0 }

                it 'should not perform any scaling operations' do
                  expect(asg).not_to receive(:set_group_size)
                end
              end

              context 'with target_size = 1' do
                let(:target_size) { 1 }

                it 'should incr the new group before decr the old' do
                  expect(asg).to receive(:set_group_size).with(new_group, 1)
                    .ordered
                  expect(asg).to receive(:set_group_size).with(old_group, 0)
                    .ordered
                end

                it 'should delete the old group upon completion' do
                  expect(old_group).to receive(:delete)
                end

                it 'should delete the old launch config upon completion' do
                  expect(old_launch_config).to receive(:delete)
                end

                context 'with services' do
                  let(:services) { ['service-1', 'service-2'] }

                  it 'should pass the services on to #instance_healthy?' do
                    expect(ec2_mock).to receive(:instance_healthy?)
                      .with(new_instance_ids[0], services, elb_names)
                  end
                end

                context 'without services' do
                  let(:services) { [] }

                  it 'should perform a health check on the new instance' do
                    expect(ec2_mock).to receive(:instance_healthy?)
                      .with(new_instance_ids[0], [], elb_names)
                  end
                end
              end # with target_size = 1

              context 'with target_size = 2' do
                let(:target_size) { 2 }

                it 'should perform a health check on all of the instances' do
                  new_instance_ids.each do |id|
                    expect(ec2_mock).to receive(:instance_healthy?)
                      .with(id, services, elb_names)
                  end
                end

                it 'should perform the health check target_size times' do
                  expect(ec2_mock).to receive(:instance_healthy?)
                    .exactly(target_size).times
                end

                it 'should increment the new group twice' do
                  expect(asg).to receive(:set_group_size).with(new_group, 1)
                    .once
                  expect(asg).to receive(:set_group_size).with(new_group, 2)
                    .once
                end

                it 'should decrement the old group twice' do
                  expect(asg).to receive(:set_group_size).with(old_group, 1)
                    .once
                  expect(asg).to receive(:set_group_size).with(old_group, 0)
                    .once
                end
              end # with target_size = 2
            end # with successful deployment

            context 'with new instances unhealthy' do
              let(:instance_healthy) { [false] }
              let(:old_group_params) do
                {
                  min_size: 1,
                  max_size: 1,
                  desired_capacity: 1
                }
              end
              let(:target_size) { 1 }

              after { subject rescue nil }

              it 'should call step_deploy_failure' do
                expect(asg).to receive(:step_deploy_failure).with(
                  instance_of(UnhealthyDeploymentError),
                  new_group,
                  old_group,
                  old_group_params
                ).and_raise(UnhealthyDeploymentError)
              end

              context 'with step_deploy_failure returning nil' do
                before do
                  retried = false
                  allow(asg).to receive(:step_deploy_failure) do
                    fail UnhealthyDeploymentError if retried
                    retried = true
                    nil
                  end
                end

                it 'should retry step deployment' do
                  expect(asg).to receive(:set_group_size)
                    .with(new_group, 1).twice
                end
              end # with step_deploy_failure returning nil

              context 'with step_deploy_failure raising error' do
                before do
                  allow(asg).to receive(:step_deploy_failure)
                    .and_raise(UnhealthyDeploymentError)
                end

                it 'should raise the error' do
                  expect { subject }.to raise_error UnhealthyDeploymentError
                end
              end # with step_deploy_failure raising error
            end # with new instances unhealthy

            context 'with AWS errors' do
              def aws_error(error_name)
                ::Aws::EC2::Errors.error_class(error_name).new('','')
              end

              let(:target_size) { 1 }

              context 'with error during new group increment' do
                let(:scale_up_error) { aws_error('ServiceError') }

                it 'should call step_deploy_failure' do
                  expect(asg).to receive(:step_deploy_failure)
                    .with(scale_up_error, new_group, old_group,
                      old_group_params)
                  subject
                end

                context 'with step_deploy_failure returning nil' do
                  before { allow(asg).to receive(:step_deploy_failure) }

                  it 'should retry step deployment' do
                    expect(asg).to receive(:set_group_size).with(new_group, 1)
                      .twice
                    subject
                  end # # with step_deploy_failure returning nil
                end # with retry selection

                context 'with step_deploy_failure raising error' do
                  before do
                    allow(asg).to receive(:step_deploy_failure)
                      .and_raise(scale_up_error)
                  end

                  it 'should raise the error' do
                    expect { subject }.to raise_error scale_up_error
                  end
                end # with step_deploy_failure raising error
              end # with error during new group increment

              context 'with error during old group decrement' do
                let(:scale_down_error) { aws_error('ServiceError') }

                it 'should call step_deploy_failure' do
                  expect(asg).to receive(:step_deploy_failure)
                    .with(scale_down_error, new_group, old_group,
                      old_group_params)
                  subject
                end

                context 'with step_deploy_failure returning nil' do
                  before { allow(asg).to receive(:step_deploy_failure) }

                  it 'should retry step deployment' do
                    expect(asg).to receive(:set_group_size).with(new_group, 1)
                      .twice
                    subject
                  end
                end # with step_deploy_failure returning nil

                context 'with step_deploy_failure raising error' do
                  before do
                    allow(asg).to receive(:step_deploy_failure)
                      .and_raise(scale_down_error)
                  end

                  it 'should raise the error' do
                    expect { subject }.to raise_error scale_down_error
                  end
                end # with step_deploy_failure raising error
              end # with error during old group decrement

              context 'with error during group teardown' do
                before do
                  allow(asg).to receive(:delete_group)
                    .and_raise(aws_error('ServiceError'))
                  allow(asg).to receive(:sleep)
                end

                after { subject rescue nil }

                it 'should attempt to delete the group 3 times' do
                  expect(asg).to receive(:delete_group).exactly(3).times
                end

                it 'should raise ServiceError' do
                  expect { subject }.to raise_error(
                    ::Aws::EC2::Errors::ServiceError
                  )
                end
              end # with error during group teardown
            end # with AWS errors
          end # with role=client

          context 'with role=server' do
            let(:role) { 'server' }
            let(:target_size) { 1 }
            let(:server_ip) { '10.2.3.0' }
            let(:leader_indexes) do
              {
                commit_index: '1234',
                last_log_index: '1235'
              }
            end

            before do
              allow(asg).to receive(:server_synced?).and_return(*server_synced)
              allow(asg).to receive(:leader_sync_indexes)
                .and_return(leader_indexes)
              allow(ec2_mock).to receive(:private_ip).and_return(server_ip)
            end

            context 'with healthy deployment' do
              let(:instance_healthy) { [true] }
              let(:server_synced) { [true] }

              it 'should ensure the server is synced' do
                expect(asg).to receive(:server_synced?)
                  .with(server_ip, '1234', '1235')
                subject
              end
            end # with healthy deployment

            context 'with unhealthy deployment' do
              after { subject rescue nil }

              context 'with server not synced' do
                let(:server_synced) { [false] }

                it 'should call step_deploy_failure' do
                  expect(asg).to receive(:step_deploy_failure)
                    .and_raise(ConsulServerNotSyncedError)
                end

                context 'with step_deploy_failure returning nil' do
                  before do
                    retried = false
                    allow(asg).to receive(:step_deploy_failure) do
                      fail ConsulServerNotSyncedError if retried
                      retried = true
                      nil
                    end
                  end

                  it 'should retry step deployment' do
                    expect(asg).to receive(:set_group_size).with(new_group, 1)
                      .twice
                  end
                end

                context 'with step_deploy_failure raising error' do
                  before do
                    allow(asg).to receive(:step_deploy_failure)
                      .and_raise(ConsulServerNotSyncedError)
                  end

                  it 'should raise the error' do
                    expect { subject }.to raise_error ConsulServerNotSyncedError
                  end
                end
              end # with server not synced
            end # with unhealthy deployment
          end # with role=server
        end # step_deploy#

        describe '#step_deploy_failure' do
          subject do
            asg.step_deploy_failure(error, new_group, old_group, orig_params)
          end

          let(:error) { ConsulServerNotSyncedError.new }
          let(:new_group) { double('new group') }
          let(:old_group) { double('old group') }
          let(:orig_params) do
            {
              desired_capacity: 3
            }
          end

          before do
            $stdin = double('stdin')
            allow($stdin).to receive(:gets).and_return("#{prompt_response}\n")
          end

          after { $stdin = STDIN }

          context 'with retry (prompt response = 1)' do
            let(:prompt_response) { '1' }

            it 'should not raise an error' do
              expect { subject }.not_to raise_error
            end

            it { is_expected.to be nil }
          end

          context 'with rollback (prompt response = 2)' do
            let(:prompt_response) { '2' }

            it 'should call step_deploy in reverse and raise the error' do
              expect(asg).to receive(:step_deploy).with(
                old_group, new_group, orig_params[:desired_capacity]
              )

              expect { subject }.to raise_error ConsulServerNotSyncedError
            end
          end
        end # #step_deploy_failure

        describe '#teardown_group' do
          subject { asg.teardown_group(group, delete_elbs) }

          let(:group) { double('group') }
          let(:group_name) { 'gr-abc123' }
          let(:waiter_mock) { double('Waiter') }
          let(:ec2_mock) { double('Resources::EC2') }
          let(:elb_mock) { double('Resources::ELB') }
          let(:delete_elbs) { true }

          around do |ex|
            Aws::Resources::EC2.mock(ec2_mock) do
              Aws::Resources::ELB.mock(elb_mock) do
                Aws::Resources::AutoScaling::Waiter.mock(waiter_mock) do
                  ex.run
                end
              end
            end
          end

          before do
            allow(group).to receive(:update).with(min_size: 0)
            allow(group).to receive(:instances).and_return(instances, [])
            allow(group).to receive(:launch_configuration)
              .and_return(launch_config)
            allow(waiter_mock).to receive(:wait_until_group_has_size)

            allow(elb_mock).to receive(:delete_load_balancer).with(
              load_balancer_name: group_name
            )
            allow(ec2_mock).to receive(:instance).and_return(ec2_instance)
            instances.each do |i|
              allow(i).to receive(:terminate).with(
                should_decrement_desired_capacity: true
              )
            end
            allow(ec2_instance).to receive(:wait_until_terminated)
            allow(group).to receive(:load_balancers).and_return(elbs)
            allow(waiter_mock).to receive(:wait_until_no_scaling_activities)
            allow(asg).to receive(:delete_group).with(group)
          end

          let(:instance_ids) { ['i-abc1234', 'i-1234abc'] }
          let(:instances) do
            instance_ids.map { |id| double("instance-#{id}", id: id) }
          end
          let(:ec2_instance) do
            double('ec2-instance', id: 'i-abc1234', state: state_obj)
          end
          let(:state_obj) { Struct.new(:name).new(instance_state) }
          let(:instance_state) { 'running' }
          let(:elbs) { [double('elb', name: group_name)] }
          let(:launch_config) { double('launch-config', delete: true) }

          after { subject }

          it 'should tear down all of the instances' do
            instances.each { |i| expect(i).to receive(:terminate).once }
          end

          it 'should delete the elb' do
            expect(elb_mock).to receive(:delete_load_balancer).with(
              load_balancer_name: group_name
            )
          end

          it 'should delete the launch configuration' do
            expect(launch_config).to receive(:delete)
          end

          it 'should delete the group' do
            expect(asg).to receive(:delete_group).with(group)
          end

          context 'with no elb' do
            let(:elbs) { [] }

            it 'should not attempt to delete the load balancer' do
              expect(elb_mock).not_to receive(:delete_load_balancer)
            end
          end

          context 'with delete_elbs=false' do
            let(:delete_elbs) { false }

            it 'should not attempt to delete the load balancer' do
              expect(elb_mock).not_to receive(:delete_load_balancer)
            end
          end

          context 'without delete_elbs param set' do
            subject { asg.teardown_group(group) }

            it 'should delete the elb by default' do
              expect(elb_mock).to receive(:delete_load_balancer).with(
                load_balancer_name: group_name
              )
            end
          end

          context 'with terminating instances' do
            let(:instance_state) { 'terminating' }
            it 'should not attempt terminating the instances' do
              instances.each { |i| expect(i).not_to receive(:terminate) }
            end
          end

          context 'with terminated instances' do
            let(:instance_state) { 'terminating' }
            it 'should not attempt terminating the instances' do
              instances.each { |i| expect(i).not_to receive(:terminate) }
            end
          end

          context 'with instances pending' do
            let(:instance_state) { 'pending' }
            it 'should wait until the instances are running' do
              expect(ec2_instance).to receive(:wait_until_running)
                .exactly(instance_ids.count).times
            end
          end
        end # #teardown_group

        describe '#delete_group' do
          subject { asg.delete_group(group) }

          after { subject }

          let(:group) { double('group') }

          before do
            allow(group).to receive(:delete)
            allow(group).to receive(:wait_until_not_exists)
          end

          it 'should delete the group' do
            expect(group).to receive(:delete)
          end

          it 'should wait until it no longer exists' do
            expect(group).to receive(:wait_until_not_exists)
          end
        end # #delete_group

        describe '#role_of' do
          subject { asg.role_of(group) }

          let(:group) { double('group') }

          before do
            allow(group).to receive(:data).and_return(group_data)
            allow(group_data).to receive(:tags).and_return(tags)
          end

          let(:group_data) { double(:group_data) }

          context 'with podbay:role = client' do
            let(:tags) do
              [
                double('tag', key: 'podbay:cluster', value: 'gr-abc1234'),
                double('tag', key: 'podbay:role', value: 'client'),
              ]
            end

            it { is_expected.to eq 'client' }
          end

          context 'without podbay:role tag' do
            let(:tags) { [] }
            it { is_expected.to eq nil }
          end
        end # #role_of

        describe '#services_of' do
          subject { asg.services_of(group) }

          let(:group) { double('group') }

          before do
            allow(group).to receive(:data).and_return(group_data)
            allow(group_data).to receive(:tags).and_return(tags)
          end

          let(:group_data) { double(:group_data) }

          context 'without static_services' do
            let(:tags) { [] }
            it { is_expected.to eq [] }
          end

          context 'with single service' do
            let(:tags) do
              [
                double('tag', key: 'podbay:modules:static_services',
                  value: 'test-service')
              ]
            end

            it { is_expected.to eq ['test-service'] }
          end

          context 'with multiple services' do
            let(:tags) do
              [
                double('tag', key: 'podbay:modules:static_services',
                  value: 'test-service1,test-service2')
              ]
            end

            it { is_expected.to eq ['test-service1', 'test-service2'] }
          end
        end # #services_of

        describe '#server_synced?' do
          subject do
            asg.server_synced?(server_ip, leader_commit_index,
              leader_last_log_index, 1, 1)
          end

          let(:mock_utils) { double('Utils') }
          let(:server_ip) { '10.2.3.1' }
          let(:consul_info) do
            {
              raft: {
                commit_index: server_commit_index,
                last_log_index: server_last_log_index
              }
            }
          end
          let(:leader_commit_index) { 0 }
          let(:leader_last_log_index) { 0 }
          let(:server_commit_index) { 0 }
          let(:server_last_log_index) { 0 }
          let(:manual_server_check) { true }

          before do
            allow(mock_utils).to receive(:podbay_info).and_return(consul_info)
            allow(mock_utils).to receive(:prompt_question)
              .and_return(manual_server_check)
          end

          around { |ex| Utils.mock(mock_utils) { ex.run } }

          it 'should make the correct request' do
            expect(mock_utils).to receive(:podbay_info)
              .with(server_ip, 'consul_info')
            subject
          end

          context 'with connection error' do
            before do
              allow(mock_utils).to receive(:podbay_info)
                .and_raise(Errno::ECONNREFUSED)
            end

            it 'should attempt to get the info 3 times' do
              expect(mock_utils).to receive(:podbay_info).exactly(3).times
              subject
            end

            context 'with manual server check = true' do
              let(:manual_server_check) { true }
              it { is_expected.to be true }
            end

            context 'with manual server check = false' do
              let(:manual_server_check) { false }
              it { is_expected.to be false }
            end
          end # with connection error

          context 'with synced consul server' do
            let(:leader_commit_index) { 100 }
            let(:leader_last_log_index) { 100 }
            let(:server_commit_index) { 100 }
            let(:server_last_log_index) { 100 }

            it { is_expected.to be true }
          end # with synced consul server

          context 'with unsynced consul server' do
            let(:leader_commit_index) { 100 }
            let(:leader_last_log_index) { 100 }
            let(:server_commit_index) { 99 }
            let(:server_last_log_index) { 99 }

            it { is_expected.to be false }
          end # with unsynced consul server
        end # #server_synced

        describe '#leader_sync_indexes' do
          subject { asg.leader_sync_indexes }

          let(:leader_info) do
            {
              raft: {
                commit_index: 123,
                last_log_index: 123
              }
            }
          end
          let(:mock_utils) { double('Utils') }
          let(:mock_consul) { double('Consul') }

          around do |ex|
            Utils.mock(mock_utils) do
              Podbay::Consul.mock(mock_consul) do
                ex.run
              end
            end
          end

          before do
            allow(mock_utils).to receive(:podbay_info).and_return(leader_info)
            allow(mock_consul).to receive(:leader_ip).and_return('10.2.3.4')
          end

          it 'should return a hash of leader indexes' do
            is_expected.to eq(
              commit_index: 123,
              last_log_index: 123
            )
          end

          context 'with connection errors' do
            before do
              allow(mock_utils).to receive(:podbay_info)
                .and_raise(Errno::ECONNREFUSED)
            end
            let(:prompt_response) { ['1235', '1234'] }

            before do
              $stdin = double('stdin')
              allow($stdin).to receive(:gets)
                .and_return(*prompt_response.map { |r| "#{r}\n" })
            end

            after { $stdin = STDIN }

            it 'should attempt to get the info 3 times' do
              expect(mock_utils).to receive(:podbay_info).exactly(3).times
              subject
            end

            it 'should return a hash of leader indexes' do
              is_expected.to eq(
                commit_index: 1235,
                last_log_index: 1234
              )
            end
          end
        end # #leader_sync_indexes
      end # AutoScaling
    end # Aws::Resources
  end # Components
end # Base
