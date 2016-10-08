require 'aws-sdk'

module Podbay
  module Components
    module Aws::Resources
      class ElastiCache
        include Mixins::Mockable

        def client
          @__client ||= ::Aws::ElastiCache::Client.new(region: region)
        end

        def region
          ENV['AWS_REGION'] || 'us-east-1'
        end

        private

        def method_missing(meth, *args, &block)
          client.public_send(meth, *args, &block)
        end

        def respond_to_missing?(meth, include_private = false)
          client.respond_to?(meth) || super
        end
      end # ElastiCache
    end # Aws::Resources
  end # Components
end # Podbay
