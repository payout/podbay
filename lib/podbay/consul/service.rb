require 'securerandom'

module Podbay
  class Consul
    class Service
      attr_reader :name

      ACTION_ROOT = 'actions/service:%s'.freeze

      def initialize(name)
        @name = name.to_sym
      end

      def lock(ttl: 15, &block)
        action_channel.lock(ttl: ttl, &block)
      end

      ##
      # Initialize an action on the service. Returns nil if the action could
      # not be initialize (i.e., another action is in progress). Otherwise,
      # returns an action hash with the action id and name.
      def begin_action(action_name, ttl: 600, data: nil)
        action_channel.begin_action(action_name, ttl: ttl, data: data)
      end

      ##
      # Refreshes an action's time to keep it alive. Returns true if the
      # refresh was successful, false if another action is in progress.
      def refresh_action(action_id, data: nil)
        action = _action_obj

        if action && action.id == action_id
          action.data = data
          action.save rescue return false
          true
        else
          false
        end
      end

      ##
      # Ends an action. Requires the passed action_id to match the current
      # action. Returns true if the action was ended successfully, and false
      # otherwise. If false is returned, it's likely that your action has
      # expired.
      def end_action(action_id)
        action = _action_obj

        if action && action.id == action_id
          action.end
        else
          false
        end
      end

      ##
      # Whether or not an action is currently in progress.
      def action?
        action_channel.in_use?
      end

      ##
      # Returns a hash for the current action. An empty hash signifies no action
      # is being taken.
      def action
        _action_obj.to_h
      end

      def action_channel
        @__action_channel ||= ActionChannel.new("service:#{name}")
      end

      private

      def _action_obj
        action_channel.current
      end

      def _action_name
        ACTION_ROOT % name
      end

      def _set_action(defn)
        Consul::Kv.set(_action_name, defn)
        defn
      end
    end # Service
  end # Consul
end # Podbay