module Podbay
  class Components::Daemon::Modules
    class Consul
      class Backups
        BACKUP_WINDOW_SIZE = 24

        class Backup
          def backup(_, _)
            fail NotImplementedError
          end

          def create_daily_snapshot(_)
            fail NotImplementedError
          end

          def retrieve(_)
            fail NotImplementedError
          end
        end # Backup
      end # Backups
    end # Consul
  end # Components::Daemon::Modules
end # Podbay
