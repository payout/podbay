require 'fileutils'
require 'base64'
require 'socket'

module Podbay
  module Components
    class Daemon
      class Modules
        class StaticServices < Base
          attr_reader :services

          def execute(*services)
            Daemon::Process.spawn do
              @services = services.map(&:to_s).map(&:freeze).freeze
              wait_for_event(:service_router_ready)
              _run_services(services)
              handle_events
            end
          end

          def handle_events
            Podbay::Consul.handle_events('action') do |e|
              _handle_event(e)
            end
          end

          private

          def _run_services(services)
            running_count = _running_services_count
            configured_count = Utils.count_values(*services.map(&:to_s))

            configured_count.each do |service, count|
              (count - running_count[service]).times do
                begin
                  daemon.launch(service)
                rescue StandardError => e
                  daemon.logger.error("Could not start #{service} due to error: #{e}")
                  daemon.logger.error("Backtrace: #{e.backtrace}")
                  STDOUT.flush
                  break
                end
              end
            end
          end

          def _running_services_count
            running_services = Docker.containers.map do |c|
              ContainerInfo.service_name(c['id'])
            end

            Utils.count_values(*running_services)
          end

          def _handle_event(event)
            send(
              "_handle_#{event['Name']}",
              Base64.strict_decode64(event['Payload'])
            )
          end

          def _handle_action(action_payload)
            channel, service_name, action_id = action_payload.split(':', 3)
            unless channel == 'service'
              daemon.logger.info("Ignoring action: #{action_payload.inspect}")
              return
            end

            service = Podbay::Consul.service(service_name)

            unless (action = service.action)[:id] == action_id
              daemon.logger.warn("Ignoring abandoned action: #{action_id}")
              return
            end

            action_method = "_handle_#{action[:name]}_action".freeze

            unless respond_to?(action_method, true)
              daemon.logger.warn("Ignoring unknown action #{action[:name]}.")
              return
            end

            send(action_method, service, action_id)
          end

          def _handle_restart_action(service, action_id)
            return unless services.include?(service.name.to_s)
            return unless _restart_sync(service, action_id)

            service.lock(ttl: 30) do |lock|
              begin
                unless (action = service.action)[:id] == action_id
                  daemon.logger.warn("Restart #{action_id} was abandoned")
                  break
                end

                data = action[:data]
                unless (state = data[:state]) == 'restart'
                  fail "Restart in unexpected state #{state}"
                end

                # This is in case restarting errors out and we release the lock.
                # The next node that gets the lock needs to know that something
                # went wrong when trying to restart last. This will cause the
                # restart to be aborted (see above).
                data[:state] = 'restarting'
                service.refresh_action(action_id, data: data)
                lock.renew if lock.ttl_remaining < 10

                _restart_service(service.name.to_s, lock)

                # Wait for the service to become healthy.
                until Podbay::Consul.service_healthy?(service.name.to_s, Socket.gethostname)
                  sleep 1
                end

                # Let the next node know that it's okay to continue.
                data[:state] = 'restart'
                data[:restarted_nodes] ||= []
                data[:restarted_nodes] |= [Socket.gethostname]

                service.refresh_action(action_id, data: data)
              rescue StandardError => e
                daemon.logger.warn(e.message)
                data[:state] = 'abort'
                service.refresh_action(action_id, data: data)
              end
            end
          end

          def _restart_sync(service, action_id)
            service.lock do |_|
              unless (action = service.action)[:id] == action_id
                daemon.logger.warn("Restart #{action_id} was abandoned")
                return false
              end

              unless (state = action[:data][:state]) == 'sync'
                daemon.logger.warn("Restart in unexpected state: #{state}")
                return false
              end

              daemon.logger.info("Syncing for restart #{action_id}")

              data = action[:data]
              data[:synced_nodes] ||= []
              data[:synced_nodes] |= [Socket.gethostname]
              service.refresh_action(action_id, data: data)
            end

            sleep 1 until service.action[:data][:state] == 'restart'
            true
          end

          def _restart_service(service_name, lock)
            daemon.logger.info("Restarting #{service_name}")
            _deregister(service_name)
            lock.renew if lock.ttl_remaining < 10
            _stop(service_name)

            lock.renew # Need to make sure there's enough time for daemon.launch

            # Only want to launch the service the originally configured
            # number of times.
            services.count { |s| s == service_name.to_s }.times do
              fail 'Docker launch error' unless daemon.launch(service_name)
              lock.renew
            end

            true
          end

          def _deregister(service_name)
            Podbay::Consul.local_services.values
              .select { |s| s['Service'] == service_name.to_s }
              .map { |s| s['ID'] }
              .each { |id| Podbay::Consul.deregister_local_service(id) }
          end

          def _stop(service_name)
            containers = Docker.containers.select do |c|
              ContainerInfo.service_name(c['id']) == service_name.to_s
            end

            containers.each { |c| Docker.stop(c['id']) }
          end
        end # StaticServices
      end # Modules
    end # Daemon
  end # Components
end # Podbay
