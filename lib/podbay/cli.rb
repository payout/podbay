module Podbay
  module CLI
    autoload(:Arguments, 'podbay/cli/arguments')

    class << self
      def run_component_command(arguments)
        klass = Components.find_component(arguments.component)
        fail "Invalid component name '#{arguments.component}'!" unless klass

        run_component_command!(klass, arguments)
      end

      def run_component_command!(component, arguments)
        component.new(arguments.options)
          .public_send(arguments.command, *arguments.args)
      end
    end # Class Methods
  end # CLI
end # Podbay