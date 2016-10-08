module Podbay
  class Consul
    class Connection
      def initialize
        # Mirroring Diplomat config for now. Later this can be replaced with
        # custom config after we remove Diplomat.
        @_conn = Faraday.new(Diplomat.configuration.url) do |faraday|
          faraday.adapter Faraday.default_adapter
          faraday.request :url_encoded
          faraday.response :raise_error
        end
      end

      def get(url, params = {})
        query = URI.encode_www_form(params)
        _request(:get, "#{url}#{query.empty? ? '' : "?#{query}"}",
          timeout: 300)
      end

      def put(url, body = nil)
        body = JSON.dump(body) if body.is_a?(Hash)
        _request(:put, url, payload: body)
      end

      def delete(url)
        _request(:delete, url)
      end

      private

      def _request(verb, url, payload: nil, timeout: 10, open_timeout: 2)
        resp = @_conn.public_send(verb) do |req|
          req.url url
          req.options.timeout = timeout if timeout
          req.options.open_timeout = open_timeout if open_timeout
          req.body = payload if payload
        end

        _prepare_response(resp)
      rescue Faraday::TimeoutError
        fail Podbay::TimeoutError
      rescue Faraday::ConnectionFailed => e
        if e.message == 'execution expired'
          fail Podbay::TimeoutError
        else
          raise
        end
      end

      def _prepare_response(resp)
        {
          status: _retrieve_status(resp),
          body: _parse_body(resp),
          index: _retrieve_index(resp)
        }
      end

      def _retrieve_status(resp)
        resp.status
      end

      def _parse_body(resp)
        if (body = resp.body) && !body.empty?
          if ['[', '{'].include?(body[0])
            JSON.parse(body)
          else
            body
          end
        end
      end

      def _retrieve_index(resp)
        resp.headers['x-consul-index']
      end
    end # Connection
  end # Consul
end # Podbay