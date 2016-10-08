require 'base64'

module Podbay
  module Components
    class Aws < Base
      include Mixins::Mockable
      mockable :cluster

      autoload(:Resources,  'podbay/components/aws/resources')
      autoload(:Validation, 'podbay/components/aws/validation')
      autoload(:Cluster,    'podbay/components/aws/cluster')
      autoload(:AwsUtils,   'podbay/components/aws/aws_utils')

      attr_reader :group_name

      def bootstrap(params = {})
        Validation.validate_bootstrap_params(params)
        _verify_appropriate_role(params[:role])
        _server_setup if params[:role] == 'server'

        @group_name = "gr-#{SecureRandom.hex(8)}".freeze
        resource_name = "#{group_name}-#{Utils.timestamp}".freeze
        dmz = params[:dmz] == 'true'

        security_group = _security_group_for(params[:role], dmz)

        instance_profile = Resources::IAM.instance_profile(
          _cluster.id_of("Podbay#{params[:role].capitalize}InstanceProfile")
        )
        unless instance_profile.exists?
          fail MissingResourceError, 'instance profile missing'
        end

        print 'Creating launch configuration... '
        Resources::AutoScaling.create_launch_configuration(
          {
            launch_configuration_name: resource_name,
            image_id: params[:ami],
            instance_type: params[:instance_type] || 't2.small',
            iam_instance_profile: instance_profile.arn,
            associate_public_ip_address: params[:dmz],
            security_groups: [security_group.id],
            user_data: Base64.encode64(_user_data(params)),
            key_name: params[:key_pair]
          }.select { |_,v| !!v }
        )
        puts 'Complete!'.green

        # Setup the AutoScaling group
        new_subnets = _create_group_subnets(dmz)
        _associate_subnets_with_route_table(dmz, new_subnets)

        new_subnet_ids = new_subnets.map(&:id)
        tags = _generate_bootstrap_tags(params)

        asg_params = {
          auto_scaling_group_name: resource_name,
          launch_configuration_name: resource_name,
          min_size: (params[:size] || 2).to_i,
          max_size: (params[:size] || 2).to_i,
          desired_capacity: (params[:size] || 2).to_i,
          health_check_grace_period: '300',
          health_check_type: 'EC2',
          vpc_zone_identifier: new_subnet_ids.join(','),
          tags: tags
        }

        if dmz && params[:elb]
          _setup_dmz_elb(new_subnet_ids, params)
          asg_params[:load_balancer_names] = [group_name]
          asg_params[:health_check_type] = 'ELB'
        end

        print 'Creating autoscaling group... '
        Resources::AutoScaling.create_group(asg_params)
        puts 'Complete!'.green

        puts "Bootstrap succeeded for group: #{group_name}".green
      end

      def teardown(group_name, params = {})
        Validation.validate_teardown_params(group_name, params)
        @group_name = group_name

        if (asg = _cluster.asg_of_group(group_name)) && asg.exists?
          Resources::AutoScaling.teardown_group(asg)
        else
          puts 'AutoScalingGroup not found, cleaning up any remaining resources'
        end

        _teardown_subnets
        puts "Teardown complete for group: #{group_name}".green
      rescue StandardError => e
        puts "Encountered a failure state, try running teardown again".red
        raise e
      end

      def upgrade(params = {})
        Validation.validate_upgrade_params(params)

        upgrade_statuses = {}
        groups = _cluster.groups
        return "No groups found for cluster #{cluster.inspect}" if groups.empty?

        group_of_this_instance = Resources::AutoScaling
          .group_of_instance(Utils::EC2.instance_id)

        groups.each do |group|
          # Deploy for every group except the group that this script is being
          # run on
          next if group.name == group_of_this_instance
          group_name = group.name.gsub(/-\d+\z/, '')

          if group.launch_configuration.image_id == params[:ami]
            puts "Skipping group #{group_name}. It's already set to use " \
              "#{params[:ami]}."

            upgrade_statuses[group_name] = 'Unchanged -- AMI already set.'.green
            next
          end

          puts "** Upgrading #{group_name} **"
          begin
            deploy(params.merge(group: group_name))
          rescue StandardError => e
            upgrade_statuses[group_name] = "Error: #{e.class}: #{e.message}".red
            puts "** Encountered an error for #{group_name}. Continuing... **"
            next
          end

          upgrade_statuses[group_name] = 'Upgraded Successfully'.green
        end

        nil
      ensure
        puts "\n"
        puts '-------------------------------'
        puts '|    Upgrade Status Report    |'
        puts '-------------------------------'
        upgrade_statuses.each { |g, s| puts g + '    ' + s }
      end

      def deploy(params = {})
        unless Podbay::Consul.ready?
          fail 'Deploy running on node with no consul agent'
        end

        Validation.validate_deploy_params(params)
        @group_name = params[:group]
        resource_name = "#{group_name}-#{Utils.timestamp}".freeze

        # Get old group's resources
        unless (prv_asg = _cluster.asg_of_group(group_name))
          fail MissingResourceError, 'AutoScalingGroup not found'
        end

        role = Resources::AutoScaling.role_of(prv_asg)
        if params[:instance_type] &&  role == 'server'
          fail 'changing server configuration is not supported'
        end

        # Copy old group's Launch configuration
        print 'Creating new Launch Configuration... '
        updated_launch_config_params = {
          image_id: params[:ami] || prv_asg.launch_configuration.image_id,
          launch_configuration_name: resource_name
        }.tap do |h|
          h[:instance_type] = params[:instance_type] if params[:instance_type]
        end
        Resources::AutoScaling.copy_launch_config(prv_asg.launch_configuration,
          updated_launch_config_params
        )
        puts 'Complete!'.green

        # Copy old group's ASG
        print 'Creating new AutoScaling Group... '
        new_asg_params = {
          auto_scaling_group_name: resource_name,
          launch_configuration_name: resource_name,
          min_size: 0,
          max_size: 0,
          desired_capacity: 0
        }
        asg = Resources::AutoScaling.copy_group(prv_asg, new_asg_params)
        puts 'Complete!'.green

        puts 'Starting Step Deployment'.blue

        _setup_deployment_interrupt_handling
        Resources::AutoScaling.step_deploy(asg, prv_asg,
          prv_asg.desired_capacity)
        puts "Deployment complete for group: #{group_name}".green
      end

      def db_setup(params = {})
        Validation.validate_db_setup_params(params)

        name = "db-#{SecureRandom.hex(8)}".freeze
        @group_name = params[:group]

        # Get group subnets (excluding any DB subnets)
        group_subnet_cidrs = _cluster.subnets_of_group(group_name).to_a
          .map { |s| { cidr_ip: s.cidr_block } }
        if group_subnet_cidrs.empty?
          fail MissingResourceError, "no valid subnets for group #{group_name}"
        end

        begin
          security_group = _setup_store_security_group('database', name,
            params[:engine], group_subnet_cidrs)
          db_subnets, db_subnet_group = _create_store_subnets('database', name)
          db = _create_db_instance(name, security_group.id, params)
        rescue StandardError => e
          print 'Encountered failure state, rolling back... '.red
          AwsUtils.cleanup_resources(db, security_group, db_subnet_group,
            db_subnets)
          puts 'Complete!'.red

          raise e
        end

        print 'Waiting until DB Instance is ready (can take a few minutes)...'
        until db.endpoint
          sleep 5
          print '.'
          db = Resources::RDS.db_instance(db.id)
        end
        puts ' Ready!'.green

        {
          name: name,
          cidrs: db_subnets.map(&:cidr_block),
          endpoint_address: db.endpoint.address,
          endpoint_port: db.endpoint.port
        }
      end

      def cache_setup(params = {})
        Validation.validate_cache_setup_params(params)

        name = "ca-#{SecureRandom.hex(6)}".freeze
        @group_name = params[:group]

        # Get group subnets (excluding any DB / Cache subnets)
        group_subnet_cidrs = _cluster.subnets_of_group(group_name).to_a
          .map { |s| { cidr_ip: s.cidr_block } }
        if group_subnet_cidrs.empty?
          fail MissingResourceError, "no valid subnets for group #{group_name}"
        end

        begin
          security_group = _setup_store_security_group('cache', name,
            params[:engine], group_subnet_cidrs)
          subnets, subnet_group = _create_store_subnets('cache', name)
          cache = _create_cache(name, security_group.id, params)
        rescue StandardError => e
          print 'Encountered failure state, rolling back... '.red
          AwsUtils.cleanup_resources(security_group, subnets)

          if subnet_group
            Resources::ElastiCache.delete_cache_subnet_group(
              cache_subnet_group_name: subnet_group.cache_subnet_group_name
            )
          end
          puts 'Complete!'.red

          raise e
        end

        print 'Waiting until ElastiCache Instance is ready ' \
          '(can take several minutes)...'
        until cache.node_groups[0]
          sleep 5
          print '.'
          cache = Resources::ElastiCache.describe_replication_groups(
            replication_group_id: cache.replication_group_id
          ).replication_groups[0]
        end
        puts ' Ready!'.green

        {
          name: name,
          cidrs: subnets.map(&:cidr_block),
          endpoint_address: cache.node_groups[0].primary_endpoint.address,
          endpoint_port: cache.node_groups[0].primary_endpoint.port
        }
      end

      def setup_gossip_encryption
        print 'Setting up initial gossip key...'
        file = Utils::SecureS3File.new(_gossip_key_file)
        file.kms_key_id = _cluster.config_key
        key = Base64.strict_encode64(SecureRandom.random_bytes(16))
        file.write(key)
        puts 'done.'.green
        nil
      end

      def setup_backup_key
        Utils::S3File.write(_backup_key_file, _cluster.podbay_key)
        nil
      end

      private

      def _cluster
        @_cluster ||= Cluster.new(cluster)
      end

      def _verify_appropriate_role(role)
        servers_exist = _cluster.servers_exist?

        case role
        when 'server'
          if servers_exist
            fail ValidationError, 'only one server group is allowed per cluster'
          end
        when 'client'
          unless servers_exist
            fail ValidationError, 'server group must be created first before ' \
              'a client group can be created'
          end
        else
          # This should never happen because the validation should catch it.
          fail "unexpected role: #{role.inspect}"
        end
      end

      def _server_setup
        ENV['AWS_REGION'] = _cluster.region
        setup_gossip_encryption
        setup_backup_key
      end

      def _gossip_key_file
        "s3://#{_cluster.config_bucket}/gossip_key"
      end

      def _backup_key_file
        "s3://#{_cluster.podbay_bucket}/all/encryption_key"
      end

      def _setup_dmz_elb(subnet_ids, params)
        # Create a load balancer if we're bootstrapping in the DMZ
        security_group = Resources::EC2.security_group(
          _cluster.id_of('DMZELBSecurityGroup')
        )
        unless Resources::EC2.security_group_exists?(security_group.id)
          fail MissingResourceError,
            'Security Group "DMZELBSecurityGroup" missing'
        end

        print 'Creating load balancer... '
        Resources::ELB.create_load_balancer(
          load_balancer_name: group_name,
          listeners: [
            {
              protocol: 'HTTP',
              load_balancer_port: 80,
              instance_protocol: 'HTTP',
              instance_port: 3001
            },
            {
              protocol: 'HTTPS',
              load_balancer_port: 443,
              instance_protocol: 'HTTP',
              instance_port: 3001,
              ssl_certificate_id: params[:elb][:ssl_certificate_arn]
            }
          ],
          subnets: subnet_ids,
          security_groups: [security_group.id],
          tags: [
            { key: 'podbay:cluster', value: cluster },
            { key: 'podbay:group', value: group_name }
          ]
        )

        Resources::ELB.set_load_balancer_policies_of_listener(
          load_balancer_name: group_name,
          load_balancer_port: 443,
          policy_names: ['ELBSecurityPolicy-2015-05']
        )

        Resources::ELB.modify_load_balancer_attributes(
          load_balancer_name: group_name,
          load_balancer_attributes: {
            cross_zone_load_balancing: { enabled: true },
            connection_draining: {
              enabled: true,
              timeout: 300
            },
            connection_settings: { idle_timeout: 60 }
          }
        )

        if params[:elb][:target]
          target = "http:3001#{params[:elb][:target]}"
        else
          target = "tcp:3001"
        end

        Resources::ELB.configure_health_check(
          load_balancer_name: group_name,
          health_check: {
            target: target,
            interval: (params[:elb][:interval] || 30).to_i,
            timeout: (params[:elb][:timeout] || 3).to_i,
            healthy_threshold: (params[:elb][:healthy_threshold] || 2).to_i,
            unhealthy_threshold: (params[:elb][:unhealthy_threshold] || 2).to_i
          }
        )
        puts 'Complete!'.green
      end

      def _create_store_subnets(store_type, name)
        unless ['database', 'cache'].include?(store_type)
          fail "invalid store type: #{store_type}"
        end

        # Create subnet group
        store_subnets = _cluster.create_subnets(
          2, false, 28, "podbay:#{store_type}" => name
        )
        _associate_subnets_with_private_route_tables(store_subnets)
        store_subnet_group = send(
          "_create_#{store_type}_subnet_group", name, store_subnets.map(&:id)
        )
        [store_subnets, store_subnet_group]
      end

      def _setup_store_security_group(store_type, name, engine, ingress_cidrs)
        unless ['database', 'cache'].include?(store_type)
          fail "invalid store type: #{store_type}"
        end

        print 'Creating Security Group... '
        security_group = Resources::EC2.create_security_group(
          group_name: name,
          description: "Security Group for #{store_type.capitalize} #{name}",
          vpc_id: _cluster.vpc.id
        )
        Resources::EC2.add_tags(security_group.id,
          'podbay:cluster' => cluster, "podbay:#{store_type}" => name)

        security_group.authorize_ingress(
          ip_permissions: [{
            ip_protocol: 'tcp',
            from_port: AwsUtils.send("default_#{store_type}_port", engine),
            to_port: AwsUtils.send("default_#{store_type}_port", engine),
            ip_ranges: ingress_cidrs
          }]
        )

        puts 'Complete!'.green
        security_group
      end

      def _security_group_for(role, dmz)
        sg_tag = "#{role.capitalize}SecurityGroup"
        sg_tag.prepend('DMZ') if role == 'client' && dmz
        security_group = Resources::EC2.security_group(_cluster.id_of(sg_tag))
        unless Resources::EC2.security_group_exists?(security_group.id)
          fail MissingResourceError,
            "security group for #{sg_tag.inspect} missing"
        end

        security_group
      end

      def _generate_bootstrap_tags(params)
       [
          {
            key: 'podbay:cluster',
            value: cluster,
            propagate_at_launch: true
          },
          {
            key: 'podbay:group',
            value: group_name,
            propagate_at_launch: true
          },
          {
            key: 'podbay:role',
            value: params[:role],
            propagate_at_launch: true
          }
        ].tap do |t|
          if params[:modules]
            params[:modules].each do |k, v|
              t.push(
                key: "podbay:modules:#{k}",
                value: v.is_a?(Array) ? v.join(',') : v,
                propagate_at_launch: true
              )
            end
          end
        end
      end

      def _associate_subnets_with_route_table(dmz, subnets)
        if dmz
          _associate_subnets_with_public_route_table(subnets)
        else
          _associate_subnets_with_private_route_tables(subnets)
        end
      end

      def _associate_subnets_with_public_route_table(subnets)
        subnets.each do |s|
          _cluster.public_route_table.associate_with_subnet(subnet_id: s.id)
        end
      end

      def _associate_subnets_with_private_route_tables(subnets)
        subnets.each do |subnet|
          az = subnet.availability_zone
          route_table = _cluster.private_route_tables.find do |rt|
            rt.tags.any? { |t| t.key == 'AvailabilityZone' && t.value == az }
          end

          if route_table
            route_table.associate_with_subnet(subnet_id: subnet.id)
          else
            fail "Route Table not found for availability zone #{az.inspect}"
          end
        end
      end

      def _create_group_subnets(dmz)
        _cluster.create_subnets(_cluster.availability_zones.length, dmz, 24,
          'podbay:group' => group_name)
      end

      def _create_db_instance(name, security_group_id, params)
        print 'Creating DB Instance... '
        Resources::RDS.create_db_instance(
          db_name: name.delete('-'),
          db_instance_identifier: name,
          allocated_storage: params[:allocated_storage],
          db_instance_class: params[:instance_class] || 'db.m3.medium',
          engine: params[:engine],
          master_username: params[:username],
          master_user_password: params[:password],
          vpc_security_group_ids: [security_group_id],
          db_subnet_group_name: name,
          preferred_maintenance_window: params[:maintenance_window],
          backup_retention_period: params[:backup_retention_period] || 7,
          preferred_backup_window: params[:backup_window],
          port: AwsUtils.default_database_port(params[:engine]),
          multi_az: params[:multi_az] || true,
          engine_version: params[:engine_version],
          auto_minor_version_upgrade: true,
          license_model: params[:license_model],
          publicly_accessible: false,
          tags: [
            { key: 'podbay:cluster', value: cluster },
            { key: 'podbay:database', value: name }
          ],
          storage_type: 'gp2',
          storage_encrypted: true
        ).tap { puts 'Complete!'.green }
      end

      def _create_cache(name, security_group_id, params)
        print 'Creating ElastiCache Instance... '
        Resources::ElastiCache.create_replication_group(
          replication_group_id: name,
          replication_group_description: "Redis Replication Group",
          automatic_failover_enabled: true,
          cache_node_type: params[:cache_node_type] || 'cache.m3.medium',
          cache_subnet_group_name: name,
          engine: params[:engine],
          engine_version: params[:engine_version],
          num_cache_clusters: _cluster.availability_zones.size,
          port: AwsUtils.default_cache_port(params[:engine]),
          security_group_ids: [security_group_id],
          snapshot_retention_limit: params[:snapshot_retention_limit] || 14,
          snapshot_window: params[:snapshot_window],
          preferred_cache_cluster_a_zs: _cluster.availability_zones,
          tags: [
            { key: 'podbay:cluster', value: cluster },
            { key: 'podbay:cache', value: name }
          ]
        ).replication_group.tap { puts 'Complete!'.green }
      end

      def _create_database_subnet_group(db_name, subnet_ids)
        print 'Creating DB Subnet Group... '
        Resources::RDS.create_db_subnet_group(
          db_subnet_group_name: db_name,
          db_subnet_group_description: "Subnet Group for #{db_name}",
          subnet_ids: subnet_ids,
          tags: [
            { key: 'podbay:cluster', value: cluster },
            { key: 'podbay:database', value: db_name }
          ]
        ).tap { puts 'Complete!'.green }
      end

      def _create_cache_subnet_group(cache_name, subnet_ids)
        print 'Creating Cache Subnet Group... '
        Resources::ElastiCache.create_cache_subnet_group(
          cache_subnet_group_name: cache_name,
          cache_subnet_group_description: "Subnet Group for #{cache_name}",
          subnet_ids: subnet_ids
        ).cache_subnet_group.tap { puts 'Complete!'.green }
      end

      def _teardown_subnets
        subnets = _cluster.subnets_of_group(group_name).to_a
        puts 'No Subnets found' if subnets.empty?

        subnets.each do |subnet|
          print "Tearing down subnet #{subnet.id}... "

          20.times do
            break if subnet.network_interfaces.to_a.empty?
            print '.'
            sleep(5)
          end

          unless (network_interfaces = subnet.network_interfaces.to_a).empty?
            fail "Subnet has network interfaces still in use: " \
              "#{network_interfaces.map(&:id).join(', ')}"
          end

          subnet.delete
          puts 'Complete!'.green
        end
      end

      def _setup_deployment_interrupt_handling
        trap('INT') do
          if Utils.prompt_question('Are you sure you want to abort ' \
            'the deployment?')
            fail Interrupt, 'Deployment interrupted'
          end
        end
      end

      def _user_data(params = {})
        user_data = (params[:modules] || {}).merge(
          consul: {
            role: params[:role],
            cluster: cluster,
            expect: params[:size],
            discovery_mode: params[:discovery_mode] || 'awstags',
            gossip_key_file: _gossip_key_file,
            storage_location: "s3://#{_cluster.podbay_bucket}"
          }.reject { |_,v| !v }
        ).reject { |_,v| !v }

        <<-TXT
#!/bin/bash
echo '#{user_data.to_json}' > /etc/podbay.conf
      TXT
      end
    end # Aws
  end # Components
end # Podbay
