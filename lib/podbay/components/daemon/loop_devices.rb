require 'csv'
require 'fileutils'

module Podbay
  class Components::Daemon
    class LoopDevices
      include Mixins::Mockable
      DEFAULT_LOOP_PATH = '/var/podbay/loop'.freeze

      attr_reader :loop_path

      def initialize(loop_path = DEFAULT_LOOP_PATH)
        @loop_path = loop_path
      end

      [:tabfile, :mounts, :files].each do |path|
        define_method("#{path}_path") do
          "#{loop_path}/#{path}"
        end
      end

      ##
      # Returns a list of all the mounted loop directories.
      def mount_paths_listing
        Dir["#{mounts_path}/*"]
      end

      ##
      # Loads from the tabfile
      # "8652bd0a\t16777216"
      #
      # Only creates the loop devices/mounts that don't exist.
      def resolve_tabfile
        File.readlines(tabfile_path).map do |line|
          line.chomp!
          unless line.empty?
            name, size, owner = line.split("\t")
            _create(name, size, owner) unless _exists?(name)
          end
        end
      end

      def create(size_b, owner)
        loop_name = SecureRandom.hex(4)
        _create(loop_name, size_b, owner)
      end

      def remove(mount_path)
        id = mount_path[/\A#{mounts_path}\/([0-9a-f]+)/, 1]
        file_path = "#{files_path}/#{id}".freeze
        system("umount -d #{mount_path}")
        _remove_from_tabfile(_parse_loop_name(mount_path))
        system("rm -rf #{mount_path}")
        system("rm -f #{file_path}")
      end

      def loop_devices
        loop_devices = {}

        if File.exist?(tabfile_path)
          File.readlines(tabfile_path).map do |line|
            line.chomp!
            unless line.empty?
              name, size, owner = line.split("\t")
              loop_devices[name] = { size: size, owner: owner }
            end
          end
        end

        loop_devices.freeze
      end

      def create_loop_dir
        FileUtils::mkdir_p(mounts_path)
        FileUtils::mkdir_p(files_path)
        FileUtils.touch(tabfile_path) unless File.exist?(tabfile_path)
      end

      private

      def _parse_loop_name(path)
        path.split('/')[-1]
      end

      ##
      # Checks if the loop device is created.
      def _exists?(loop_name)
        `losetup -a`.include? loop_name
      end

      def _create(loop_name, size_b, owner)
        file_path = "#{files_path}/#{loop_name}"
        mount_path = "#{mounts_path}/#{loop_name}"

        # setup loop device
        system("fallocate -l #{size_b} #{file_path}")
        loop_device = `losetup --show --sizelimit #{size_b} -f #{file_path}`
          .chomp

        # format and mount
        system("mke2fs #{loop_device}")
        system("mkdir -p #{mount_path}")
        system("mount -o nosuid,nodev,noexec #{loop_device} #{mount_path}")
        system("chown -R #{owner}:#{owner} #{mount_path}")

        _write_to_tabfile(loop_name, size_b, owner)
        mount_path
      end

      def _write_to_tabfile(loop_name, size_b, owner)
        unless loop_devices.key?(loop_name)
          File.open(tabfile_path, 'a') do |file|
            file.write("#{loop_name}\t#{size_b}\t#{owner}\n")
          end
        end
      end

      def _remove_from_tabfile(loop_name)
        accepted_content = File.readlines(tabfile_path).reject {
          |line| line =~ /#{loop_name}/
        }
        File.open(tabfile_path, 'w') do |f|
          accepted_content.each { |line| f.puts line }
        end
      end
    end
  end
end