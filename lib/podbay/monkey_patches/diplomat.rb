require 'diplomat'

module Diplomat
  class Timeout < StandardError; end
end

module Diplomat
  class Service
    def get_all(options = nil)
      url = ["/v1/catalog/services"]
      url << use_named_parameter('dc', options[:dc]) if options and options[:dc]

      if options and options[:index]
        url << use_named_parameter('index', options[:index])
      end

      begin
        ret = @conn.get concat_url url
        index = ret.headers && ret.headers["x-consul-index"]
      rescue Faraday::TimeoutError
        raise Diplomat::Timeout
      rescue Faraday::ClientError
        raise Diplomat::PathNotFound
      end

      return [JSON.parse(ret.body), index]
    end
  end
end

module Diplomat
  class Status < Diplomat::RestClient
    @access_methods = [:leader]

    def leader
      if (body = @conn.get('/v1/status/leader').body) && body.is_a?(String)
        body[1..-2]
      end
    end
  end
end
