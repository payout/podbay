require 'aws-sdk'

module Podbay
  module Components
    module Aws::Resources
      class ELB
        include Mixins::Mockable

        def client
          @__client ||= ::Aws::ElasticLoadBalancing::Client.new(region: region)
        end

        def region
          ENV['AWS_REGION'] || 'us-east-1'
        end

        def elb_exists?(name)
          !!describe_load_balancers(load_balancer_names: [name])
        rescue ::Aws::ElasticLoadBalancing::Errors::LoadBalancerNotFound
          false
        end

        def elbs_healthy?(elb_names)
          print "Waiting for ELB health checks to pass..."
          elb_names.each do |elb_name|
            begin
              wait_until(:instance_in_service,
                load_balancer_name: elb_name) do |waiter|
                waiter.before_wait { print '.' }
              end
            rescue ::Aws::Waiters::Errors::WaiterFailed
              return false
            end
          end

          puts ' Complete!'.green
          true
        end

        private

        def method_missing(meth, *args, &block)
          client.public_send(meth, *args, &block)
        end

        def respond_to_missing?(meth, include_private = false)
          client.respond_to?(meth) || super
        end
      end # ELB
    end # Aws::Resources
  end # Components
end # Podbay
