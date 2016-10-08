module Podbay
  class Consul
    class Kv
      class << self
        def mock(mock)
          @_instance = mock
          yield
        ensure
          @_instance = nil
        end

        private

        def method_missing(meth, *args, &block)
          _instance.public_send(meth, *args, &block)
        end

        def respond_to_missing?(meth, include_private = false)
          _instance.respond_to?(meth, false, include_private)
        end

        def _instance
          @_instance ||= new
        end
      end # Class Methods

      def get(root, opts = {})
        data = store.get(root, opts)

        if data.is_a?(String) && ['{', '['].include?(data[0])
          JSON.parse(data, symbolize_names: true)
        else
          data
        end
      rescue Diplomat::KeyNotFound
        nil
      end

      def set(root, object)
        data = object.is_a?(Hash) || object.is_a?(Array) ? JSON.dump(object)
          : object.to_s
        store.put(root, data)
      end

      def delete(root)
        store.delete(root)
        true
      end

      def store
        @_store ||= Diplomat::Kv.new
      end

      def mock_store(store)
        @_store = store
        yield
      ensure
        @_store = nil
      end
    end # Kv
  end # Consul
end # Podbay