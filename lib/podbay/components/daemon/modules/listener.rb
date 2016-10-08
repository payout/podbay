require 'webrick'
require 'json'

module Podbay
  module Components
    class Daemon
      class Modules
        class Listener < Base
          def execute
            spawn_opts = { user: 'consul', group: 'consul' }.freeze
            Process.spawn(spawn_opts) { run_server_info }
          end

          def run_server_info
            server = WEBrick::HTTPServer.new(Port: Podbay::SERVER_INFO_PORT)
            server.mount('/', Servlet)
            trap('TERM') do
              server.stop
              exit 0
            end
            server.start
          end

          class Servlet < WEBrick::HTTPServlet::AbstractServlet
            def do_GET(request, response)
              if request.path =~ /\A\/(\w+)\z/
                meth = "handle_#{Regexp.last_match[1]}"
                if respond_to?(meth)
                  public_send(meth, request, response)
                else
                  response.status = 404
                end
              else
                response.status = 400
              end
            end

            def handle_consul_info(request, response)
              # `consul info` returns values like this:
              # raft:
              #   applied_index = 184990
              #   commit_index = 184990
              #   fsm_pending = 0
              #   last_contact = 31.525326ms
              #   last_log_index = 184990
              #   last_log_term = 1188
              #   last_snapshot_index = 180712
              #   last_snapshot_term = 1145
              # Parse these values into a hash and #to_i the values if possible
              if request.path == '/consul_info'
                consul_info = {}
                cur_section = nil
                `consul info`.split("\n").map(&:strip).each do |str|
                  if str.include?(':')
                    cur_section = consul_info[str.tr(':', '')] = {} # New section
                  else
                   # Parse the key/vals
                    key, val = str.split(/\s*=\s*/)
                    next unless key
                    val = val.to_i if /\A([1-9][0-9]*|0)\z/.match(val)
                    cur_section[key] = val
                  end
                end

                response.status = 200
                response.body = consul_info.to_json
              else
                response.status = 404
              end
            end
          end # Servlet
        end # Listener
      end # Modules
    end # Daemon
  end # Components
end # Podbay
