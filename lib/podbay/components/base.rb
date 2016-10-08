module Podbay
  module Components
    class Base
      attr_reader :options

      def initialize(options = {})
        @options = options.dup.freeze
      end

      def service
        options[:service] or fail '--service must be specified'
      end

      def cluster
        options[:cluster] or fail '--cluster must be specified'
      end
    end # Base
  end # Components
end # Podbay
