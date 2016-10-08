module Podbay::Mixins
  module Mockable
    class << self
      def included(base)
        base.extend(ClassMethods)
      end
    end

    module ClassMethods
      def mock(mock)
        orig_instance, @_instance = @_instance, mock
        yield
      ensure
        @_instance = orig_instance
      end

      def mockable(*vars)
        vars.each do |var|
          define_method("mock_#{var}") do |mock, &block|
            begin
              orig = instance_variable_get("@_#{var}")
              instance_variable_set("@_#{var}", mock)
              block.call
            ensure
              instance_variable_set("@_#{var}", orig)
            end
          end
        end
      end

      private

      def method_missing(meth, *args, &block)
        _instance.public_send(meth, *args, &block)
      end

      def respond_to_missing?(meth, include_private = false)
        _instance.respond_to?(meth)
      end

      def _instance
        @_instance ||= new
      end
    end # ClassMethods
  end # Mockable
end # Podbay::Mixins
