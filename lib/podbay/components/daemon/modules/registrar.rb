module Podbay
  module Components
    class Daemon
      class Modules
        class Registrar < Base
          def execute(on_or_off = 'on', events_store_max = 1000)
            return if on_or_off == 'off'
            Daemon::Process.spawn do
              wait_for_consul
              wait_for_docker
              register_running_containers
              _process_events(events_store_max)
            end
          end

          def register(container_id)
            if (info = Docker.inspect_container(container_id))
              state = info['State']

              unless state['Status'] == 'running'
                daemon.logger.warn("Skipping registration for #{container_id} "\
                  "because it is #{state['Status']}")
                return
              end

              defn = _container_info_to_service_defn(info)
              if _service_defined?(defn['Name'])
                Podbay::Consul.register_service(defn)
              else
                daemon.logger.warn("Skipping registration for #{container_id} "\
                  "because #{defn['Name']} is not a defined service.")
              end
            else
              daemon.logger.error("Could not register #{container_id} because "\
                'it does not exist.')
            end
          end

          def deregister(container_id)
            Podbay::Consul.deregister_local_service(container_id)
          end

          def register_running_containers
            Docker.containers.each { |c| register(c['id']) }
          end

          private

          def _service_defined?(service_name)
            !Podbay::Consul.get_service_definition(service_name).empty?
          end

          ##
          # Blocks waiting for container start events. Calls #register for each
          # container that is started.
          def _process_events(events_store_max)
            time = Time.now.to_i
            filters = '{"type":["container"],"event":["start","die"]}'.freeze

            events_store = []

            loop do
              begin
                Docker.stream_events(since: time, filters: filters) do |e|
                  event = {time: e.time, id: e.id, status: e.status}

                  unless events_store.include?(event)
                    case event[:status]
                    when 'start'
                      register(event[:id])
                      events_store << event
                    when 'die'
                      deregister(event[:id])
                      events_store << event
                    end
                  end

                  events_store.shift if events_store.size > events_store_max
                  time = event[:time]
                end
              rescue ::Docker::Error::TimeoutError
                # Continue streaming
              end
            end
          end

          def _container_info_to_service_defn(info)
            container_id = info['Id'].freeze
            service_name = ContainerInfo.service_name(container_id) or
              fail "could not determine service name for #{container_id}"

            host_config = info['HostConfig']
            ports = _port_bindings_to_ports(
              host_config && host_config['PortBindings']
            )

            port = ports.sort.first if ports && !ports.empty?

            defn = {
              'ID' => container_id,
              'Name' => service_name,
              'Address' => Utils.local_ip
            }

            defn.merge!('Port' => port) if port

            check = ::Podbay::Consul.get_service_check(defn['Name'])
            if check && !check.empty?
              defn.merge!('Check' => _create_service_check(check, port).dup)
            end

            defn
          end

          def _create_service_check(check, port)
            consul_check = {}

            if (http = check['HTTP'])
              fail "can't define http check if no port is bound" unless port
              consul_check['HTTP'] = "http://localhost:#{port}#{http}"
            elsif (tcp = check['TCP']) && tcp.downcase == 'true'
              fail "can't define tcp check if no port is bound" unless port
              consul_check['TCP'] = "localhost:#{port}"
            elsif (script = check['Script'])
              consul_check['Script'] = script
            elsif (ttl = check['TTL'])
              consul_check['TTL'] = ttl
            end

            if ['HTTP', 'TCP', 'Script'].include?(consul_check.keys.last)
              consul_check['Interval'] = check['Interval'] || '30s'
            end

            consul_check
          end

          def _port_bindings_to_ports(pb)
            return [] unless pb
            pb.flat_map { |_,v| v.map { |x| x['HostPort'] } }.compact
              .map(&:to_i)
          end
        end # Registrar
      end # Modules
    end # Daemon
  end # Components
end # Podbay
