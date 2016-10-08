require 'fileutils'
require 'date'

module Podbay
  module Components
    class Daemon
      class Modules
        class GarbageCollector < Base
          DEFAULT_GC_INTERVAL_SECONDS = 3600 # 1 hour
          TAR_RETENTION_DAYS = 1 # 1 day

          def execute(period: DEFAULT_GC_INTERVAL_SECONDS)
            Daemon::Process.spawn do
              loop do
                collect
                sleep(period)
              end
            end
          end

          def collect
            daemon.logger.info('Garbage collection started...')
            _gc_docker
            _gc_loop_devices
            _gc_container_info
            _gc_image_tars
            daemon.logger.info('Garbage collection completed.')
            STDOUT.flush
          end

          private

          def _gc_docker
            system('docker ps -a -q | xargs --no-run-if-empty docker rm ' \
              '> /dev/null 2>&1')
            system('docker images -q | xargs --no-run-if-empty docker rmi ' \
              '> /dev/null 2>&1')
          end

          def _gc_loop_devices
            loop_mounts = Docker.containers.flat_map do |container|
              lm = Docker.container_binds(container['id']).select do |b|
                b.start_with?(LoopDevices.mounts_path)
              end

              lm.map { |m| m.split(':').first }
            end

            (LoopDevices.mount_paths_listing - loop_mounts).each do |mount_path|
              LoopDevices.remove(mount_path)
            end
          end

          def _gc_container_info
            cids = Docker.containers.map { |c| c['id'] }
            old = ContainerInfo.list - cids
            old.each { |cid| ContainerInfo.cleanup(cid) }
          end

          def _gc_image_tars
            image_tars_path = "#{Daemon::IMAGE_TARS_PATH}/**/*"
            _older_than_days(Dir.glob(image_tars_path), TAR_RETENTION_DAYS) do |file|
              FileUtils.rm(file) if File.file?(file)
            end
          end

          def _older_than_days(files, days)
            now = Date.today
            files.each do |file|
              yield file if (now - File.stat(file).mtime.to_date) > days
            end
          end
        end # GarbageCollector
      end # Modules
    end # Daemon
  end # Components
end # Podbay
