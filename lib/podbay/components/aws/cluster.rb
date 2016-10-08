module Podbay
  class Components::Aws
    class Cluster
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def formatted_name
        name.gsub(/[ _]/, '-').gsub(/[^a-zA-Z0-9-]/, '').downcase
      end

      def vpc
        @__vpc ||= Resources::EC2.vpc(
          stack.resource('VPC').physical_resource_id
        ).tap do |vpc|
          unless Resources::EC2.vpc_exists?(vpc.id)
            fail MissingResourceError, "VPC for cluster '#{name}' missing"
          end
        end
      end

      def vpc_cidr
        vpc.cidr_block
      end

      def availability_zones
        @__azs ||= Resources::EC2.tags_of(vpc)
          .select { |k,_| k.to_s.match(/\Aaz\d\z/) }
          .sort.map(&:last).tap do |azs|
            if azs.empty?
              fail MissingResourceError, 'Availability Zone(s) VPC tags missing'
            end
        end
      end

      def public_route_table
        @__public_route_table ||= Resources::EC2.route_table(
          id_of('PublicRouteTable')
        )
      end

      def private_route_tables
        @__private_route_tables ||= Resources::EC2.route_tables(
          filters: [
            {
              name: 'route-table-id',
              values: (1..availability_zones.count).map do |i|
                stack.resource("PrivateRouteTable#{i}").physical_resource_id
              end
            }
          ]
        )
      end

      def stack
        @__cf_stack ||= Resources::CloudFormation.stack(name).tap do |s|
          unless s.exists?
            fail MissingResourceError, "CloudFormation stack '#{name}' missing"
          end
        end
      end

      def config_bucket
        @__config_bucket ||= stack.resource('ConfigBucket').physical_resource_id
      end

      def config_key
        @__config_key ||= stack.resource('ConfigKey').physical_resource_id
      end

      def podbay_bucket
        @__podbay_bucket ||= stack.resource('PodbayBucket').physical_resource_id
      end

      def podbay_key
        @__podbay_key ||= stack.resource('PodbayKey').physical_resource_id
      end

      def region
        Resources::EC2.region
      end

      def servers_exist?
        if @__servers_exist.nil?
          @__servers_exist = !Resources::EC2.instances(
            filters: [
              { name: 'tag:podbay:cluster', values: [name] },
              { name: 'tag:podbay:role', values: ['server'] },
              { name: 'instance-state-name', values: ['running'] }
            ]
          ).to_a.empty?
        end

        @__servers_exist
      end

      def create_subnets(count, dmz, mask, tags)
        number_of_azs = availability_zones.length
        fail "count must be <= #{number_of_azs}" unless number_of_azs <= count

        cidrs = _pick_cidrs(count, dmz, mask)

        subnets = cidrs.each_with_index.map do |cidr, i|
          print "Creating subnet #{cidr}... "
          Resources::EC2.create_subnet(
            cidr_block: cidr,
            availability_zone: availability_zones[i],
            vpc_id: vpc.id
          ).tap do |subnet|
            loop do
              break if Resources::EC2.subnet_exists?(subnet.id)
              sleep 1
            end

            puts 'Complete!'.green
          end
        end

        Resources::EC2.add_tags(subnets.map(&:id),
          tags.merge('podbay:cluster' => name)
        )
        subnets
      end

      def groups
        Resources::AutoScaling.groups.select do |g|
          g.data.tags.any? { |t| t.key == 'podbay:cluster' && t.value == name }
        end
      end

      def asg_of_group(group_name)
        ec2_instances = Resources::EC2.instances(
          filters: [
            { name: 'tag:podbay:cluster', values: [name] },
            { name: 'tag:podbay:group', values: [group_name] },
            { name: 'instance-state-name', values: ['running'] }
          ]
        ).to_a
        return nil if ec2_instances.empty?

        asg_instances = Resources::AutoScaling.instances(
          instance_ids: ec2_instances.map(&:id)
        )

        if (gnames = asg_instances.map(&:group_name).uniq).count > 1
          fail PodbayGroupError,
            "More than 1 AutoScaling Group found: #{gnames.inspect}."
        end

        asg_instances.first && asg_instances.first.group
      end

      def subnets_of_group(group_name)
        subnets([{ name: 'tag:podbay:group', values: [group_name] }])
      end

      def subnets(filters = [])
        vpc.subnets(filters: filters)
      end

      def id_of(logical_id)
        stack.resource(logical_id).physical_resource_id
      end

      private

      def _pick_cidrs(count, dmz, mask)
        used_subnet_cidrs = subnets.map(&:cidr_block)
        count.times.inject([]) do |c|
          cidr = Utils.pick_available_cidr(vpc_cidr, used_subnet_cidrs + c,
            dmz: dmz, mask: mask)
          fail 'no IPs available for subnet' unless cidr
          c << cidr
        end
      end
    end # Cluster
  end # Components::Aws
end # Podbay
