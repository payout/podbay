module Podbay
  class Components::Daemon
    class Modules
      class Base
        include Mixins::Mockable

        attr_reader :daemon

        def initialize(daemon)
          @daemon = daemon
        end

        def execute
          fail NotImplementedError
        end

        def signal_event(event, path = daemon.event_file)
          fail 'missing event_file' unless path

          File.open(path, File::RDWR|File::CREAT, 0) do |file|
            file.flock(File::LOCK_EX)

            unless _event_in_file?(event, file)
              file.seek(0, IO::SEEK_END)
              file.write("#{event}\n")
              file.flush
            end
          end
        end

        def event_signaled?(event, path = daemon.event_file)
          if File.file?(path)
            File.open(path, 'r') do |file|
              file.flock(File::LOCK_SH)
              _event_in_file?(event, file)
            end
          end
        end

        def wait_for_event(event, path = daemon.event_file)
          loop { break if event_signaled?(event, path) }
        end

        def wait_for_consul
          loop { break if Podbay::Consul.ready? }
        end

        def wait_for_docker
          loop { break if Podbay::Docker.ready? }
        end

        private

        def _event_in_file?(event, file)
          file.read.split("\n").include?(event.to_s)
        end
      end # Base
    end # Modules
  end # Components::Daemon
end # Podbay
