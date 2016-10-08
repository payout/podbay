module Podbay
  class Utils
    class EC2
      include Mixins::Mockable

      def identity
        curl = 'curl http://169.254.169.254/latest/dynamic/instance-identity/' \
          'document 2> /dev/null'.freeze

        @__ec2_identity ||= JSON.parse(`#{curl}`)
      end

      def instance_id
        identity['instanceId']
      end

      def region
        ENV['AWS_REGION'] || identity['region']
      end
    end # EC2
  end # Utils
end # Podbay
