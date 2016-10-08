module Podbay::Components
  class Daemon
    class Process
      class << self
        def spawn(command = nil, options = nil, &block)
          _new_instance.spawn(command, options, &block)
        end

        def mock(mock)
          @_mock = mock
          yield
        ensure
          @_mock = nil
        end

        private

        def _new_instance
          @_mock || new
        end
      end # Class Methods

      attr_reader :command
      attr_reader :block
      attr_reader :options
      attr_reader :pid

      ##
      # Spawns a separate process running the specified command and returns
      # the PID of the new process.
      def spawn(command = nil, options = nil, &block)
        fail 'already spawned' if spawned?

        if command.is_a?(Hash) && options.nil?
          options = command
          command = nil
        end

        @command = command.dup.freeze if command
        @block = block.dup.freeze if block
        fail 'cannot specify both command and block' if command && block
        fail 'must specify either command or block' unless command || block

        @options = (options || {}).dup.freeze
        _spawn
      end

      def spawned?
        !!@pid
      end

      def respawn
        return unless spawned?
        reap
        _spawn
      end

      # Send SIGKILL to the process group.
      def kill
        _signal_group('KILL')
      end

      # Send SIGTERM to the process group.
      def term
        _signal_group('TERM')
      end

      def sig_usr1
        _signal_group('USR1')
      end

      def exited?
        if !spawned? || ::Process.wait(@pid, ::Process::WNOHANG)
          @pid = nil
          true
        else
          false
        end
      rescue Errno::ECHILD
        @pid = nil
        true
      end

      ##
      # Sends SIGTERM to the process and all children spawned by that process.
      # If the main process does not exit within 10 seconds, it will send a
      # SIGKILL to the process group.
      def reap
        return unless spawned?

        term
        wait_count = 0

        loop do
          break if exited?
          kill if (wait_count += 1) >= 100
          sleep(0.1)
        end

        nil
      end

      def to_s
        "#{command.split(' ').first} [#{pid}]"
      end

      private

      def _spawn
        @pid = fork do
          ::Process.setsid
          Signal.trap('TERM') { exit 0 }

          if (uname = options[:user])
            uid = Podbay::Utils.get_uid(uname)
            gid = Podbay::Utils.get_gid(gname = options[:group] || uname)

            Daemon.logger.info('Process dropping privileges to ' \
              "#{uname}:#{gname} UID: #{uid} GID: #{gid}")

            ::Process::Sys.setgid(gid)
            ::Process::Sys.setuid(uid)
          end

          command && ::Process.exec(command) || block.call
        end

        # Give the forked process a little time to establish a new session with
        # setsid.
        sleep 0.05

        self
      end

      def _signal_group(sig)
        if (pid = @pid)
          ::Process.kill("-#{sig}", pid)
        end
      rescue Errno::ESRCH
        @pid = nil
      rescue Errno::EPERM
        # This happens when the primary process is a zombie
      end
    end
  end # Daemon
end # Podbay::Components
