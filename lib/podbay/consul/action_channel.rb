require 'securerandom'

module Podbay
  class Consul
    class ActionChannel
      include Mixins::Mockable
      attr_reader :name

      ACTION_KEY_ROOT = 'actions/%s'.freeze

      def initialize(name)
        @name = name.to_sym
      end

      def lock(ttl: 15)
        if @__current_lock
          yield @__current_lock
        else
          Consul.lock("action:#{name}", ttl: ttl) do |lock|
            begin
              yield (@__current_lock = lock)
            ensure
              @__current_lock = nil
            end
          end
        end
      end

      ##
      # Initialize an action on the service. Returns nil if the action could
      # not be initialize (i.e., another action is in progress). Otherwise,
      # returns an action hash with the action id and name.
      def begin_action(action_name, ttl: 600, data: nil)
        lock do
          now = Time.now.to_i

          crt_action = current

          if !crt_action || crt_action.expired?
            action = Action.new(self,
              id: SecureRandom.uuid,
              name: action_name,
              time: now,
              ttl: ttl,
              data: data
            )
            action.save

            Consul.fire_event('action', "#{name}:#{action.id}")
            action
          end
        end
      end

      ##
      # Ends an action. Requires the passed action to match the current
      # action. Returns true if the action was ended successfully, and false
      # otherwise. If false is returned, it's likely that your action has
      # expired.
      def end_action(action)
        lock { !!(Consul::Kv.delete(_action_key) if current.id == action.id) }
      end

      ##
      # Whether or not an action is currently in progress.
      def in_use?
        !!current
      end

      ##
      # Returns a hash for the current action. Nil signifies no action
      # is being taken.
      def current
        defn = Consul::Kv.get(_action_key)
        Action.new(self, defn) if defn
      end

      def set_action(action)
        lock do
          if !(crt = current) || (crt.id == action.id && !crt.expired?)
            defn = action.to_h
            defn[:time] = Time.now.to_i
            Consul::Kv.set(_action_key, defn)
            defn
          else
            fail Podbay::ActionExpiredError
          end
        end
      end

      private

      def _action_key
        ACTION_KEY_ROOT % name
      end
    end # ActionChannel
  end # Consul
end # Podbay
