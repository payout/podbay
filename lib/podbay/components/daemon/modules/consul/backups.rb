module Podbay
  class Components::Daemon::Modules
    class Consul
      class Backups
        include Mixins::Mockable

        autoload(:Backup,
          'podbay/components/daemon/modules/consul/backups/backup')
        autoload(:S3Backup,
          'podbay/components/daemon/modules/consul/backups/s3_backup')

        def load(uri)
          const_name = (uri.scheme.to_s + '_backup').camelcase.to_sym

          if self.class.constants.include?(const_name)
            if (const = self.class.const_get(const_name)).is_a?(Class)
              const.new(uri)
            end
          end
        end
      end # Backups
    end # Consul
  end # Components::Daemon::Modules
end # Podbay
