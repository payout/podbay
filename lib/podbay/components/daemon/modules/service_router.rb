require 'fileutils'

module Podbay
  module Components
    class Daemon
      class Modules
        class ServiceRouter < Base
          mockable :file_writer

          TEMPLATE_PATH = File.expand_path('../../../../../../templates',
            __FILE__).freeze
          PODBAY_CONFIG_DIR = '/etc/podbay'.freeze
          PODBAY_HOSTS_PATH = "#{PODBAY_CONFIG_DIR}/hosts".freeze
          HAPROXY_CONFIG_PATH = '/etc/haproxy/haproxy.cfg'.freeze
          SSH_PORT = 22
          COSNUL_SERVER_RPC_PORT = 8300
          SERF_LAN_PORT = 8301
          SERF_WAN_PORT = 8302
          CONSUL_CLI_RPC_PORT = 8400
          CONSUL_HTTP_API_PORT = 8500
          CONSUL_DNS_PORT = 8600

          def execute
            Daemon::Process.spawn do
              wait_for_consul
              _setup_iptables
              monitor_services
            end
          end

          def monitor_services
            index = _sync(nil)
            signal_event(:service_router_ready)

            loop { index = _sync(index) }
          end

          private

          def _file_writer
            @_file_writer ||= proc do |path, &block|
              dir = File.dirname(path)
              FileUtils.mkdir_p(dir) unless File.directory?(dir)
              File.open(path, 'w') { |file| block.call(file) }

              # This is needed in case the host system has a hardened UMASK
              # that makes files private by default.
              FileUtils.chmod(0644, path)
            end
          end

          def _iptables_input_drop_from_podbay(protocol, port)
            Iptables.chain('INPUT').rule("-s #{Daemon::PODBAY_NETWORK_CIDR} " \
              "-m addrtype --dst-type LOCAL -i #{daemon.bridge_tag} " \
              "-p #{protocol} --dport #{port} -j DROP").insert_if_needed(2)
          end

          def _iptables_forward_drop_from_podbay(protocol, port)
            Iptables.chain('FORWARD').rule("-s #{Daemon::PODBAY_NETWORK_CIDR} "\
              "-i #{daemon.bridge_tag} -p #{protocol} " \
              "--dport #{port} -j DROP").insert_if_needed
          end

          def _setup_iptables
            # INPUT chain DROP rules
            _iptables_input_drop_from_podbay('tcp', SSH_PORT)
            _iptables_input_drop_from_podbay('tcp', COSNUL_SERVER_RPC_PORT)
            _iptables_input_drop_from_podbay('tcp', SERF_LAN_PORT)
            _iptables_input_drop_from_podbay('udp', SERF_LAN_PORT)
            _iptables_input_drop_from_podbay('tcp', SERF_WAN_PORT)
            _iptables_input_drop_from_podbay('udp', SERF_WAN_PORT)
            _iptables_input_drop_from_podbay('tcp', CONSUL_CLI_RPC_PORT)
            _iptables_input_drop_from_podbay('tcp', CONSUL_HTTP_API_PORT)
            _iptables_input_drop_from_podbay('tcp', CONSUL_DNS_PORT)
            _iptables_input_drop_from_podbay('udp', CONSUL_DNS_PORT)

            # FORWARD chain DROP rules
            _iptables_forward_drop_from_podbay('tcp', SSH_PORT)
            _iptables_forward_drop_from_podbay('tcp', COSNUL_SERVER_RPC_PORT)
            _iptables_forward_drop_from_podbay('tcp', SERF_LAN_PORT)
            _iptables_forward_drop_from_podbay('udp', SERF_LAN_PORT)
            _iptables_forward_drop_from_podbay('tcp', SERF_WAN_PORT)
            _iptables_forward_drop_from_podbay('udp', SERF_WAN_PORT)
            _iptables_forward_drop_from_podbay('tcp', CONSUL_CLI_RPC_PORT)
            _iptables_forward_drop_from_podbay('tcp', CONSUL_HTTP_API_PORT)
            _iptables_forward_drop_from_podbay('tcp', CONSUL_DNS_PORT)
            _iptables_forward_drop_from_podbay('udp', CONSUL_DNS_PORT)

            # ACCEPT rules for outbound traffic
            Iptables.chain('INPUT').rule("-s #{Daemon::PODBAY_NETWORK_CIDR} " \
              "-m addrtype --dst-type LOCAL -i #{daemon.bridge_tag} " \
              "-j ACCEPT").append_if_needed

            Iptables.chain('PODBAY_EGRESS').rule("-d #{PODBAY_IP_TEMPLATE % 1}"\
              " -j ACCEPT").insert_if_needed(2)
          end

          def _sync(index)
            service_details = {}

            services, index = Podbay::Consul.available_services(index)
            services.each do |service|
              defn = Podbay::Consul.get_service_definition(service) || {}
              host = defn[:host]
              addresses, _ = Podbay::Consul.service_addresses!(service)

              service_details[service] = {
                host: host || "#{service}.podbay.internal",
                addresses: addresses
              }
            end

            _filter_addresses(service_details)
            _update_hosts(service_details)
            _update_haproxy(service_details)
            index
          end

          def _filter_addresses(service_details)
            checks = Podbay::Consul.health_checks

            service_details.each do |_, details|
              details[:addresses].reject! do |address|
                checks.any? do |check|
                  check['ServiceID'] == address[:id] &&
                    !['passing', 'warning'].include?(check['Status'])
                end
              end
            end
          end # #_filter_addresses

          def _update_hosts(service_details)
            hosts = service_details.map { |_,d| d[:host] }
            return if defined?(@__hosts) && (hosts - @__hosts).empty?
            @__hosts = hosts

            daemon.logger.info("Updating #{PODBAY_HOSTS_PATH.inspect}...")

            template = File.read("#{TEMPLATE_PATH}/etc/podbay/hosts.erb")

            b = binding

            _file_writer.call(PODBAY_HOSTS_PATH) do |file|
              file.write(ERB.new(template, nil, '-').result(b))
            end

            daemon.logger.info("Done updating #{PODBAY_HOSTS_PATH.inspect}")
          end

          def _update_haproxy(service_details)
            return if defined?(@__haproxy_service_details) &&
              @__haproxy_service_details == service_details

            daemon.logger.info("Updating #{HAPROXY_CONFIG_PATH.inspect}...")

            template = File.read("#{TEMPLATE_PATH}/etc/haproxy/haproxy.cfg.erb")

            b = binding
            _file_writer.call(HAPROXY_CONFIG_PATH) do |file|
              file.write(ERB.new(template, nil, '-').result(b))
            end

            daemon.logger.info("Done updating #{HAPROXY_CONFIG_PATH.inspect}")
            daemon.logger.info('Reloading haproxy...')

            if system('service haproxy reload')
              daemon.logger.info('Reloaded haproxy successfully.')
              @__haproxy_service_details = service_details.dup.freeze
            else
              daemon.logger.error('Failed to reload haproxy.')
            end
          end
        end # ServiceRouter
      end # Modules
    end # Daemon
  end # Components
end # Podbay
