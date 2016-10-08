module Podbay
  module Components
    module Aws::Resources
      class EC2 < Base
        ##
        # This method has to be created because the aws-sdk currently doesn't
        # support #exists? for a VPC resource...
        def vpc_exists?(vpc_id)
          !!vpc(vpc_id).vpc_id
        rescue ::Aws::EC2::Errors::InvalidVpcIDNotFound
          false
        end

        def subnet_exists?(subnet_id)
          !!subnet(subnet_id).subnet_id
        rescue ::Aws::EC2::Errors::InvalidSubnetIDNotFound
          false
        end

        def security_group_exists?(sg_id)
          !!security_group(sg_id).vpc_id
        rescue ::Aws::EC2::Errors::InvalidGroupNotFound
          false
        end

        def private_ip(instance_id)
          instance(instance_id).private_ip_address
        end

        def hostname(instance_id)
          instance(instance_id).private_dns_name.gsub(/\.ec2\.internal\z/, '')
        end

        def add_tags(resource_ids, tags = {})
          ids = resource_ids.is_a?(Array) ? resource_ids : [resource_ids]

          create_tags(
            resources: ids,
            tags: tags.map { |k,v| { key: k, value: v }}
          )
        end

        def instance_healthy?(instance_id, services, elb_names)
          Podbay::Consul.node_healthy?(hostname(instance_id), services) &&
            (elb_names.empty? || ELB.elbs_healthy?(elb_names))
        end
      end # EC2
    end # Aws::Resources
  end # Components
end # Podbay
