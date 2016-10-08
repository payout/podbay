module Podbay
  module Components
    class Version < Base
      def execute
        puts "Podbay v#{Podbay::VERSION}"
      end
    end # Version
  end # Components
end # Podbay
