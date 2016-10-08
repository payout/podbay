require 'fileutils'

class Podbay::Components::Daemon
  class ContainerInfo
    include Podbay::Mixins::Mockable

    INFO_PATH = '/var/podbay/containers'.freeze

    def write_service_name(container_id, service_name, path: INFO_PATH)
      FileUtils.mkdir_p(path)
      File.write("#{path}/#{container_id}", service_name)
    end

    def service_name(container_id, wait: 5, path: INFO_PATH)
      path = "#{path}/#{container_id}"

      if wait
        5.times do
          break if File.exist?(path)
          sleep wait / 5.0
        end
      end

      File.read(path) if File.exist?(path)
    end

    def list(path: INFO_PATH)
      Dir["#{path}/*"].map { |c| c[path.length + 1..-1] }
    end

    def cleanup(container_id, path: INFO_PATH)
      File.delete("#{path}/#{container_id}")
    end
  end
end
