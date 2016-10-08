module Podbay
  class Consul
    class Lock
      attr_reader :name
      attr_reader :sid
      attr_reader :ttl

      def initialize(name, ttl)
        @name = name.to_s.dup.freeze
        @ttl = ttl
      end

      ##
      # Block until a lock is obtained.
      def lock
        @sid = Consul.create_session("for lock #{name}", ttl: ttl).freeze
        _update_expires_at

        sleep_time = [[ttl / 100.0, 1].min, 0.01].max
        renew_time = ttl * 0.9

        slept_time = 0
        until Consul.try_lock(name, sid)
          sleep(sleep_time)

          if (slept_time += sleep_time) > renew_time
            slept_time = 0
            renew
          end
        end

        # Make sure we don't return a lock that's near expiration.
        renew if slept_time > ttl / 20.0

        nil
      end

      def unlock
        return unless @sid
        Consul.release_lock(name, sid)
        Consul.destroy_session(sid)
        @expires_at = @sid = nil
      end

      def ttl_remaining
        @expires_at - Time.now.to_f
      end

      def renew
        Consul.renew_session(sid)
        _update_expires_at
      end

      private

      def _update_expires_at
        @expires_at = Time.now.to_f + ttl - (ttl / 100.0)
      end
    end
  end # Consul
end # Podbay