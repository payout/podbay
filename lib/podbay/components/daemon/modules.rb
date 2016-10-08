module Podbay
  class Components::Daemon
    class Modules
      include Mixins::Mockable

      autoload(:Base,             'podbay/components/daemon/modules/base')
      autoload(:Consul,           'podbay/components/daemon/modules/consul')
      autoload(:Registrar,        'podbay/components/daemon/modules/registrar')

      autoload(:GarbageCollector,
        'podbay/components/daemon/modules/garbage_collector')
      autoload(:ServiceRouter,
        'podbay/components/daemon/modules/service_router')
      autoload(:StaticServices,
        'podbay/components/daemon/modules/static_services')
      autoload(:Listener, 'podbay/components/daemon/modules/listener')

      def load(name)
        if self.class.constants.include?(const_name = name.to_s.camelcase.to_sym)
          if (const = self.class.const_get(const_name)).is_a?(Class)
            return const
          end
        end

        fail "module not found #{const_name}"
      end

      def execute(name, daemon, *args)
        load(name).new(daemon).execute(*args)
      end
    end # Modules
  end # Components::Daemon
end # Podbay
