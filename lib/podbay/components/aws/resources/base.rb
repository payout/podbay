require 'aws-sdk'

module Podbay
  module Components
    module Aws::Resources
      class Base
        include Mixins::Mockable

        def resource_interface
          @__interface ||= resource_class.new(region: region)
        end

        def resource_class
          ::Aws.const_get(self.class.name.split('::').last).const_get(:Resource)
        end

        def region
          ENV['AWS_REGION'] || 'us-east-1'
        end

        def tags_of(resource)
          fail 'resource cannot have tags' unless resource.respond_to?(:tags)
          Hash[resource.tags.map { |tag| [tag.key.to_sym, tag.value] }]
        end

        private

        def method_missing(meth, *args, &block)
          resource_interface.public_send(meth, *args, &block)
        end

        def respond_to_missing?(meth, include_private = false)
          resource_interface.respond_to?(meth) || super
        end
      end # Base
    end # Aws::Resources
  end # Components
end # Podbay