module Podbay
  class Consul
    class Action
      attr_reader :channel
      attr_reader :id
      attr_reader :name
      attr_reader :time
      attr_reader :ttl
      attr_accessor :data

      def initialize(channel, defn = {})
        @channel = channel
        _load_defn(defn)
      end

      ##
      # Refreshes the local Action from the data in consul.
      #
      # Raises an error if this action has expired.
      def refresh
        crt = channel.current

        if crt.id == id
          @time = crt.time
          fail Podbay::ActionExpiredError if expired?
          @data = crt.data
        else
          fail Podbay::ActionExpiredError
        end
      end

      def lock(ttl: 15)
        channel.lock(ttl: ttl) do |lock|
          refresh
          yield lock
        end
      end

      def [](key)
        @data[key]
      end

      def []=(key, value)
        @data[key] = value
      end

      ##
      # Saves the Action data in consul.
      #
      # Raises an error if the action has expired.
      def save
        _load_defn(channel.set_action(self))
      end

      ##
      # Ends the action
      #
      # No error is raised if the action has already been ended or expired.
      def end
        channel.end_action(self)
      end

      def expired?
        time + ttl < Time.now.to_i
      end

      def to_h
        {
          id: id,
          name: name,
          time: time,
          ttl: ttl,
          data: data
        }
      end

      private

      def _load_defn(defn)
        @id = defn[:id] && defn[:id].dup.freeze
        @name = defn[:name] && defn[:name].dup.freeze
        @time = defn[:time]
        @ttl = defn[:ttl]
        @data = defn[:data] || {}
      end
    end # Action
  end # Consul
end # Podbay