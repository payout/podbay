module Podbay::Components
  class Daemon::Modules
    RSpec.describe ServiceRouter do
      let(:daemon) { Daemon.new }
      let(:service_router) { ServiceRouter.new(daemon) }

      describe '#execute', :execute do
        subject { service_router.execute }
        let(:pid) { subject.pid }

        let(:iptables) { double('Daemon::Iptables') }
        let(:consul) { double('Consul') }
        let(:file_writer) { double('file_writer') }
        let(:available_services_resp) { [['service-name'], index] }
        let(:index) { 1 }
        let(:file_double) { double('file_double') }
        let(:haproxy_reload_status) { true }
        let(:logger) { double('Daemon.logger') }
        let(:bridge_tag) { 'br-abcdefghi' }
        let(:ssh_port) { 22 }
        let(:consul_server_rpc_port) { 8300 }
        let(:serf_lan_port) { 8301 }
        let(:serf_wan_port) { 8302 }
        let(:consul_cli_rpc_port) { 8400 }
        let(:consul_http_api_port) { 8500 }
        let(:consul_dns_port) { 8600 }

        around do |ex|
          Daemon::Iptables.mock(iptables) do
            Podbay::Consul.mock(consul) do
              service_router.mock_file_writer(file_writer) do
                ex.run
              end
            end
          end
        end

        before do
          allow(consul).to receive(:ready?).and_return(true)

          allow(iptables).to receive(:chain)
            .and_return(
              double('chain',
                rule: double('rule',
                  append_if_needed: nil,
                  insert_if_needed: nil
                )
              )
            )

          allow(daemon).to receive(:bridge_tag).and_return(bridge_tag)
          allow(service_router).to receive(:monitor_services)
        end

        after { subject.reap }
        def should_exit_with(code)
          _, status = ::Process.wait2(pid)
          expect(status.exitstatus).to eq code
        end

        it { is_expected.to be_a Daemon::Process }


        it 'should insert rule into INPUT to REJECT ssh_port' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p tcp --dport #{ssh_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 7 }
          should_exit_with(7)
        end

        it 'should insert rule into INPUT to REJECT consul_server_rpc_port' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p tcp --dport #{consul_server_rpc_port} " \
            "-j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 8 }
          should_exit_with(8)
        end

        it 'should insert rule into INPUT to REJECT tcp serf_lan' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p tcp --dport #{serf_lan_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 9 }
          should_exit_with(9)
        end

        it 'should insert rule into INPUT to REJECT udp serf_lan' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p udp --dport #{serf_lan_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 10 }
          should_exit_with(10)
        end

        it 'should insert rule into INPUT to REJECT tcp serf_wan_port' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p tcp --dport #{serf_wan_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 11 }
          should_exit_with(11)
        end

        it 'should insert rule into INPUT to REJECT udp serf_wan_port' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p udp --dport #{serf_wan_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 12 }
          should_exit_with(12)
        end

        it 'should insert rule into INPUT to REJECT consul_cli_rpc_port' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p tcp --dport #{consul_cli_rpc_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 13 }
          should_exit_with(13)
        end

        it 'should insert rule into INPUT to REJECT consul_http_api_port' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p tcp --dport #{consul_http_api_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 14 }
          should_exit_with(14)
        end

        it 'should insert rule into INPUT to REJECT tcp consul_dns_port' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p tcp --dport #{consul_dns_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 15 }
          should_exit_with(15)
        end

        it 'should insert rule into INPUT to REJECT udp consul_dns_port' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            " -p udp --dport #{consul_dns_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(2).once { exit 16 }
          should_exit_with(16)
        end

        it 'should insert rule into FORWARD to REJECT ssh_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}" \
            " -p tcp --dport #{ssh_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 17 }
          should_exit_with(17)
        end

        it 'should insert rule into FORWARD to REJECT consul_server_rpc_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}" \
            " -p tcp --dport #{consul_server_rpc_port}" \
            " -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 18 }
          should_exit_with(18)
        end

        it 'should insert rule into FORWARD to REJECT tcp serf_lan_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}"\
            " -p tcp --dport #{serf_lan_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 19 }
          should_exit_with(19)
        end

        it 'should insert rule into FORWARD to REJECT udp serf_lan_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}"\
            " -p udp --dport #{serf_lan_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 20 }
          should_exit_with(20)
        end

        it 'should insert rule into FORWARD to REJECT tcp serf_wan_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}"\
            " -p tcp --dport #{serf_wan_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 21 }
          should_exit_with(21)
        end

        it 'should insert rule into FORWARD to REJECT udp serf_wan_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}"\
            " -p udp --dport #{serf_wan_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 22 }
          should_exit_with(22)
        end

        it 'should insert rule into FORWARD to REJECT consul_cli_rpc_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}"\
            " -p tcp --dport #{consul_cli_rpc_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 23 }
          should_exit_with(23)
        end

        it 'should insert rule into FORWARD to REJECT consul_http_api_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}"\
            " -p tcp --dport #{consul_http_api_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
          .once { exit 24 }
          should_exit_with(24)
        end

        it 'should insert rule into FORWARD to REJECT tcp consul_dns_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}"\
            " -p tcp --dport #{consul_dns_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 25 }
          should_exit_with(25)
        end

        it 'should insert rule into FORWARD to REJECT udp consul_dns_port' do
          chain = double('FORWARD chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('FORWARD')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -i #{bridge_tag}"\
            " -p udp --dport #{consul_dns_port} -j DROP").and_return(rule)
          allow(rule).to receive(:insert_if_needed).with(no_args)
            .once { exit 26 }
          should_exit_with(26)
        end

        it 'should insert rule into INPUT chain with ACCEPT jump' do
          chain = double('INPUT chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(chain)
          allow(chain).to receive(:rule)
            .and_return(double(insert_if_needed: nil))
          allow(chain).to receive(:rule).with(
            "-s 192.168.100.0/24 -m addrtype --dst-type LOCAL -i #{bridge_tag}"\
            ' -j ACCEPT').and_return(rule)
          allow(rule).to receive(:append_if_needed).with(no_args)
            .once{ exit 27 }
          should_exit_with(27)
        end

        it 'should insert rule into PODBAY_EGRESS chain' do
          chain = double('PODBAY_EGRESS chain')
          rule = double('rule')
          allow(iptables).to receive(:chain).with('PODBAY_EGRESS')
            .and_return(chain)
          allow(chain).to receive(:rule).with(
            '-d 192.168.100.1 -j ACCEPT'
          ).and_return(rule)

          allow(rule).to receive(:insert_if_needed).with(2).once{ exit 28 }
          should_exit_with(28)
        end

      end # #execute

      describe '#monitor_services', :monitor_services do
        subject { service_router.monitor_services }

        let(:iptables) { double('Daemon::Iptables') }
        let(:consul) { double('Consul') }
        let(:file_writer) { double('file_writer') }
        let(:available_services_resp) { [['service-name'], index] }
        let(:index) { 1 }
        let(:get_service_definition_resp) { { host: service_hostname } }
        let(:service_hostname) { nil }
        let(:service_addresses_resp) { [addresses, nil] }
        let(:addresses) { [] }
        let(:health_checks_resp) { [] }
        let(:file_double) { double('file_double') }
        let(:haproxy_reload_status) { true }
        let(:logger) { double('Daemon.logger') }
        let(:bridge_tag) { 'br-abcdefghi' }

        around do |ex|
          Daemon::Iptables.mock(iptables) do
            Podbay::Consul.mock(consul) do
              service_router.mock_file_writer(file_writer) do
                ex.run
              end
            end
          end
        end

        before do
          allow(service_router).to receive(:loop).and_yield
          allow(consul).to receive(:available_services)
            .and_return(available_services_resp)
          allow(consul).to receive(:get_service_definition)
            .and_return(get_service_definition_resp)
          allow(consul).to receive(:service_addresses!)
            .and_return(service_addresses_resp)
          allow(consul).to receive(:health_checks)
            .and_return(health_checks_resp)

          allow(file_writer).to receive(:call) do |&block|
            block.call(file_double)
          end

          allow(file_double).to receive(:write)

          allow(service_router).to receive(:system)
            .and_return(haproxy_reload_status)

          allow(daemon).to receive(:logger).and_return(logger)
          allow(logger).to receive(:info)
          allow(logger).to receive(:error)
        end

        after { subject }

        def expect_haproxy_backend(backend_matcher, count = 1)
          file = double('file')
          allow(file_writer).to receive(:call)
            .with('/etc/haproxy/haproxy.cfg') { |&block| block.call(file) }

          expect(file).to receive(:write).with(
            a_string_matching(
              Regexp.new(
                "\nbackend service-name\n" \
                "        balance roundrobin\n" \
                "        option httpclose\n" +
                ("        #{backend_matcher}\n") * count
              )
            )
          ).once
        end

        context 'with available_services returning single service' do
          let(:available_services_resp) { [['service-name'], index] }

          it 'should call Consul.service_addresses! with service' do
            expect(consul).to receive(:service_addresses!).with('service-name')
              .twice
          end

          it 'should write to correct hosts file' do
            expect(file_writer).to receive(:call).with('/etc/podbay/hosts')
              .once
          end

          context 'with no hostname defined' do
            let(:service_hostname) { nil }

            it 'should write correct data to hosts file' do
              file = double('file')
              allow(file_writer).to receive(:call)
                .with('/etc/podbay/hosts') { |&block| block.call(file) }

              expect(file).to receive(:write).with(
                "127.0.0.1 localhost\n" \
                "::1 localhost ip6-localhost ip6-loopback\n" \
                "fe00::0 ip6-localnet\n" \
                "ff00::0 ip6-mcastprefix\n" \
                "ff02::1 ip6-allnodes\n" \
                "ff02::2 ip6-allrouters\n" \
                "192.168.100.1 service-name.podbay.internal\n"
              ).once
            end
          end # with no hostname defined

          context 'with custom hostname defined' do
            let(:service_hostname) { 'my.custom.host.name' }

            it 'should write correct data to hosts file' do
              file = double('file')
              allow(file_writer).to receive(:call)
                .with('/etc/podbay/hosts') { |&block| block.call(file) }

              expect(file).to receive(:write).with(
                "127.0.0.1 localhost\n" \
                "::1 localhost ip6-localhost ip6-loopback\n" \
                "fe00::0 ip6-localnet\n" \
                "ff00::0 ip6-mcastprefix\n" \
                "ff02::1 ip6-allnodes\n" \
                "ff02::2 ip6-allrouters\n" \
                "192.168.100.1 my.custom.host.name\n"
              ).once
            end
          end # with custom hostname defined

          context 'with service_addresses! returning no addresses' do
            let(:addresses) { [] }

            it 'should write to correct haproxy config file' do
              allow(file_writer).to receive(:call)
                .with('/etc/haproxy/haproxy.cfg').once
            end

            it 'should write set global config correctly' do
              file = double('file')
              allow(file_writer).to receive(:call)
                .with('/etc/haproxy/haproxy.cfg') { |&block| block.call(file) }

              expect(file).to receive(:write).with(
                a_string_starting_with(
                  "global\n" \
                  "        log 127.0.0.1  local0\n" \
                  "        chroot /var/lib/haproxy\n" \
                  "        user haproxy\n" \
                  "        group haproxy\n" \
                  "        daemon\n"
                )
              ).once
            end

            it 'should write set defaults correctly' do
              file = double('file')
              allow(file_writer).to receive(:call)
                .with('/etc/haproxy/haproxy.cfg') { |&block| block.call(file) }

              expect(file).to receive(:write).with(
                a_string_including(
                  "\ndefaults\n" \
                  "        log     global\n" \
                  "        mode    http\n" \
                  "        option  httplog\n" \
                  "        option  dontlognull\n" \
                  "        contimeout 5000\n" \
                  "        clitimeout 50000\n" \
                  "        srvtimeout 50000\n" \
                  "        errorfile 400 /etc/haproxy/errors/400.http\n" \
                  "        errorfile 403 /etc/haproxy/errors/403.http\n" \
                  "        errorfile 408 /etc/haproxy/errors/408.http\n" \
                  "        errorfile 500 /etc/haproxy/errors/500.http\n" \
                  "        errorfile 502 /etc/haproxy/errors/502.http\n" \
                  "        errorfile 503 /etc/haproxy/errors/503.http\n" \
                  "        errorfile 504 /etc/haproxy/errors/504.http\n"
                )
              ).once
            end

            it 'should write set frontend router block correctly' do
              file = double('file')
              allow(file_writer).to receive(:call)
                .with('/etc/haproxy/haproxy.cfg') { |&block| block.call(file) }

              expect(file).to receive(:write).with(
                a_string_including(
                  "\nfrontend router\n" \
                  "        bind 192.168.100.1:80\n" \
                  "\n" \
                  "\n" \
                  "        default_backend default_error\n"
                )
              ).once
            end

            it 'should write set default_backend correctly' do
              file = double('file')
              allow(file_writer).to receive(:call)
                .with('/etc/haproxy/haproxy.cfg') { |&block| block.call(file) }

              expect(file).to receive(:write).with(
                a_string_ending_with(
                  "backend default_error\n" \
                  "        errorfile 503 /etc/haproxy/errors/503.http\n"
                )
              ).once
            end
          end # with service_addresses! returning no addresses

          context 'with service_addresses! returning addresses' do
            let(:addresses) do
              [
                {id: 'id1', ip: '10.0.0.10', port: 3001},
                {id: 'id2', ip: '10.0.0.10', port: 3002}
              ]
            end

            it 'should write to correct haproxy config file' do
              allow(file_writer).to receive(:call)
                .with('/etc/haproxy/haproxy.cfg').once
            end

            context 'with no hostname defined' do
              let(:service_hostname) { nil }

              it 'should write set frontend router block correctly' do
                file = double('file')
                allow(file_writer).to receive(:call)
                  .with('/etc/haproxy/haproxy.cfg') { |&block| block.call(file) }

                expect(file).to receive(:write).with(
                  a_string_including(
                    "\nfrontend router\n" \
                    "        bind 192.168.100.1:80\n" \
                    "        acl is_service-name hdr(host) " \
                      "-i service-name.podbay.internal\n" \
                    "\n" \
                    "        use_backend service-name if is_service-name\n" \
                    "\n" \
                    "        default_backend default_error\n"
                  )
                ).once
              end
            end # with no hostname defined

            context 'with hostname defined' do
              let(:service_hostname) { 'custom.hostname.com' }

              it 'should write set frontend router block correctly' do
                file = double('file')
                allow(file_writer).to receive(:call)
                  .with('/etc/haproxy/haproxy.cfg') { |&block| block.call(file) }

                expect(file).to receive(:write).with(
                  a_string_including(
                    "\nfrontend router\n" \
                    "        bind 192.168.100.1:80\n" \
                    "        acl is_service-name hdr(host) " \
                      "-i custom.hostname.com\n" \
                    "\n" \
                    "        use_backend service-name if is_service-name\n" \
                    "\n" \
                    "        default_backend default_error\n"
                  )
                ).once
              end
            end # with no hostname defined

            context 'with neither container having a health check defined' do
              let(:health_checks_resp) { [] }

              it 'should use both containers in the backend' do
                expect_haproxy_backend(
                  'server id[1-2] 10.0.0.10:300[1-2] check', 2
                )
              end
            end # with neither container having a health check defined

            context 'with both containers having passing health checks' do
              let(:health_checks_resp) do
                [
                  { 'ServiceID' => 'id1', 'Status' => 'passing' },
                  { 'ServiceID' => 'id2', 'Status' => 'passing' }
                ]
              end

              it 'should use both containers in the backend' do
                expect_haproxy_backend(
                  'server id[1-2] 10.0.0.10:300[1-2] check', 2
                )
              end
            end # with both containers having passing health checks

            context 'with id1 passing and id2 critical' do
              let(:health_checks_resp) do
                [
                  { 'ServiceID' => 'id1', 'Status' => 'passing' },
                  { 'ServiceID' => 'id2', 'Status' => 'critical' }
                ]
              end

              it 'should only use id1 in the backend' do
                expect_haproxy_backend('server id1 10.0.0.10:3001 check')
              end
            end # with id1 passing and id2 critical

            context 'with id1 critical and id2 passing' do
              let(:health_checks_resp) do
                [
                  { 'ServiceID' => 'id1', 'Status' => 'critical' },
                  { 'ServiceID' => 'id2', 'Status' => 'passing' }
                ]
              end

              it 'should only use id2 in the backend' do
                expect_haproxy_backend('server id2 10.0.0.10:3002 check')
              end
            end # with id1 passing and id2 critical

            context 'with id1 warning and id2 unknown' do
              let(:health_checks_resp) do
                [
                  { 'ServiceID' => 'id1', 'Status' => 'warning' },
                  { 'ServiceID' => 'id2', 'Status' => 'unknown' }
                ]
              end

              it 'should only use id1 in the backend' do
                expect_haproxy_backend('server id1 10.0.0.10:3001 check')
              end
            end # with id1 warning and id2 unknown

            context 'with id1 passing and no id2 check' do
              let(:health_checks_resp) do
                [
                  { 'ServiceID' => 'id1', 'Status' => 'passing' }
                ]
              end

              it 'should use both containers in the backend' do
                expect_haproxy_backend(
                  'server id[1-2] 10.0.0.10:300[1-2] check', 2
                )
              end
            end # with id1 warning and no id2 check

            context 'with non-service health checks' do
              let(:health_checks_resp) do
                [
                  { 'ServiceID' => '', 'Status' => 'passing' },
                  { 'ServiceID' => '', 'Status' => 'critical' }
                ]
              end

              it 'should use both containers in the backend' do
                expect_haproxy_backend(
                  'server id[1-2] 10.0.0.10:300[1-2] check', 2
                )
              end
            end # with non-service health checks
          end # with service_addresses! returning addresses
        end # with available_services returning single service

        context 'with service addresses unchanged' do
          let(:service_addresses_resp) { [addresses, nil] }
          let(:addresses) { [{id: 's1', ip: '10.0.0.10', port: '3001'}] }
          before { allow(service_router).to receive(:loop).and_yield.and_yield }

          it 'should only write to haproxy.cfg once' do
            expect(file_writer).to receive(:call)
              .with(ServiceRouter::HAPROXY_CONFIG_PATH).once
            expect(file_double).to receive(:write)
              .with(a_string_including('server s1 10.0.0.10:3001')).once
          end
        end # with service addresses unchanged
      end # #monitor_services
    end # ServiceRouter
  end # Daemon::Modules
end # Podbay::Components
