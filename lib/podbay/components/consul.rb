require 'time'

module Podbay
  module Components
    class Consul < Base

      def gossip_rotate_key
        event_name = Podbay::Consul::GOSSIP_KEY_ROTATION_EVENT_NAME

        Podbay::Consul.lock(:gossip_rotate_key, ttl: 600) do |lock|
          Podbay::Consul.fire_event(event_name)

          print 'Syncing'
          if _wait_for_flag(:gossip_rotate_key_begin, ttl: 60)
            puts ' done'.green
            print 'Rotating'

            lock.renew

            if _wait_for_flag(:gossip_rotate_key_end, ttl: 599)
              puts ' done'.green
            else
              puts 'timed out'.yellow
              puts 'Process did not complete. Check server logs for details.'
            end
          else
            puts 'failed'.red
            puts 'Master server did not respond.'.red
          end
        end
      end

      def kv_restore(restoration_time = Time.now.to_s)
        restoration_time = Time.parse(restoration_time)

        action = Podbay::Consul.begin_action(
          Podbay::Consul::RESTORE_KV_EVENT_NAME,
          ttl: 60,
          data: { state: 'restoring', restoration_time: restoration_time }
        ) or fail 'another action is in progress'

        loop do
          sleep 1
          action.refresh
          state = action[:state]

          break if state == 'restored'

          if state == 'failed'
            puts 'Restoration failed'.red
            return
          end
        end

        puts "KVs successfully restored to #{action[:time_restored_to]}".green
      ensure
        action && action.end
      end

      private

      def _wait_for_flag(flag, ttl: 60)
        Podbay::Consul.wait_for_flag(flag, ttl: ttl) { print '.' }
      end
    end # Consul
  end # Components
end # Podbay
