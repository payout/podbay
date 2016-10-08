require 'securerandom'
require 'erb'
require 'uri'

module Podbay
  module Components
    RSpec.describe Daemon do
      let(:daemon) { Daemon.new(options) }
      let(:options) { {} }

      before do
        allow(daemon).to receive(:reinitialize_logger)
      end

      let(:docker_net_resp_with_containers) do
        ERB.new(<<-JSON
        [
          {
            "Name": "br-podbay",
            "Id": "ba6b9dba6dac499f5a8f3b1d8552d1262f748c5323e9dff2cbc0ea660ddef5a0",
            "Scope": "local",
            "Driver": "bridge",
            "IPAM": {
              "Driver": "default",
              "Options": {},
              "Config": [
                {
                  "Subnet": "192.168.100.0/24"
                }
              ]
            },
            "Containers": {
              <% container_ips[0..-2].each do |ip| %>
              "<%= SecureRandom.hex(32) %>": {
                "Name": "<%= SecureRandom.hex(6) %>_<%= SecureRandom.hex(6) %>",
                "EndpointID": "<%= SecureRandom.hex(32) %>",
                "MacAddress": "<%= SecureRandom.hex(6).scan(/../).join(':') %>",
                "IPv4Address": "<%= ip %>",
                "IPv6Address": ""
              },
              <% end %>
              <% if container_ips.last %>
              "<%= SecureRandom.hex(32) %>": {
                "Name": "<%= SecureRandom.hex(6) %>_<%= SecureRandom.hex(6) %>",
                "EndpointID": "<%= SecureRandom.hex(32) %>",
                "MacAddress": "<%= SecureRandom.hex(6).scan(/../).join(':') %>",
                "IPv4Address": "<%= container_ips.last %>",
                "IPv6Address": ""
              }
              <% end %>
            },
            "Options": {
              "com.docker.network.bridge.enable_icc": "false"
            }
          }
        ]
        JSON
        ).result(binding)
      end

      let(:container_ips) do
        ['192.168.100.2/24', '192.168.100.3/24', '192.168.100.5/24']
      end

      describe '#setup_network', :setup_network do
        subject { daemon.setup_network }

        let(:docker_create_net_resp) { '19f670effd159bd639e182cce1c15eb02b3f3' \
          'fd32b87dbf6eeef09d247698c0d' }

        before do
          expect(daemon).to receive(:`).with('docker network inspect '\
            'br-podbay 2> /dev/null')
            .and_return(docker_resp)

          allow(daemon).to receive(:`).with(a_string_starting_with('docker ' \
            'network create -o "com.docker.network.bridge.enable_icc"="false" '\
            '--subnet=192.168.100.0/24 br-podbay'))
            .and_return(docker_create_net_resp)
        end

        context 'with valid network existing' do
          let(:docker_resp) { docker_net_resp_with_containers }
          it { is_expected.to eq 'br-ba6b9dba6dac' }
        end

        context 'with network not existing' do
          # This is what docker returns before the network has been created.
          let(:docker_resp) { "null\n" }
          it { is_expected.to eq 'br-19f670effd15' }
        end

        context 'with subnet invalid' do
          let(:docker_resp) do
            docker_net_resp_with_containers.sub('192.168.100.0/24',
              '192.168.200.0/24')
          end

          context 'with containers running' do
            before { expect(daemon).to receive(:system).and_return(false) }

            it 'should raise expected error' do
              expect { subject }.to raise_error 'br-podbay is corrupted. ' \
                'Cannot clean because containers are running in it.'
            end
          end

          context 'with containers not running' do
            let(:docker_create_net_resp) { '123456789012499f5a8f3b1d8552d1262f'\
              '748c5323e9dff2cbc0ea660ddef5a0' }

            before do
              expect(daemon).to receive(:system).and_return(true)
            end

            it { is_expected.to eq 'br-123456789012' }
          end
        end # with invalid subnet

        context 'with icc enabled' do
          let(:docker_resp) do
            docker_net_resp_with_containers.sub(
              '"com.docker.network.bridge.enable_icc": "false"', ''
            )
          end

          context 'with containers running' do
            before { expect(daemon).to receive(:system).and_return(false) }

            it 'should raise expected error' do
              expect { subject }.to raise_error 'br-podbay is corrupted. ' \
                'Cannot clean because containers are running in it.'
            end
          end

          context 'with containers not running' do
            before do
              expect(daemon).to receive(:system).and_return(true)

              expect(daemon).to receive(:`).with('docker network create -o ' \
                '"com.docker.network.bridge.enable_icc"="false" '\
                "--subnet=192.168.100.0/24 br-podbay")
                .and_return('123456789012499f5a8f3b1d8552d1262f748c5323e9dff2c'\
                  'bc0ea660ddef5a0')
            end

            it { is_expected.to eq 'br-123456789012' }
          end
        end # with icc enabled

        context 'with network not created already' do
          let(:docker_resp) { '[]' }

          before do
            expect(daemon).to receive(:`).with('docker network create -o ' \
                '"com.docker.network.bridge.enable_icc"="false" '\
                "--subnet=192.168.100.0/24 br-podbay")
                .and_return(bridge_hash)
          end

          context 'with valid bridge_hash' do
            let(:bridge_hash) do
              '098765432109499f5a8f3b1d8552d1262f748c5323e9dff2cbc0ea660ddef5a0'
            end

            it { is_expected.to eq 'br-098765432109' }
          end

          context 'with valid bridge_hash' do
            let(:bridge_hash) { '' }

            it 'should raise expected error' do
              expect { subject }.to raise_error 'could not create network'
            end
          end
        end # with network not created already
      end # #setup_network

      describe '#setup_iptables', :setup_iptables do
        let(:bridge_tag) { 'br-tag' }
        subject { daemon.setup_iptables(bridge_tag) }

        let(:iptables) { double('iptables') }
        let(:ingress_chain) { double('ingress_chain') }
        let(:egress_chain) { double('egress_chain') }
        let(:forward_chain) { double('forward_chain') }
        let(:input_chain) { double('input_chain') }
        let(:output_chain) { double('output_chain') }
        around { |ex| Daemon::Iptables.mock(iptables) { ex.run } }

        # God, forgive me...
        it 'should make expected iptables calls' do
          expect(iptables).to receive(:chain).with('PODBAY_INGRESS')
            .and_return(ingress_chain)
          expect(iptables).to receive(:chain).with('PODBAY_EGRESS')
            .and_return(egress_chain)
          expect(iptables).to receive(:chain).with('INPUT')
            .and_return(input_chain)
          expect(iptables).to receive(:chain).with('FORWARD')
            .and_return(forward_chain)
          expect(iptables).to receive(:chain).with('OUTPUT')
            .and_return(output_chain)

          expect(ingress_chain).to receive(:create_if_needed).once
          expect(egress_chain).to receive(:create_if_needed).once
          expect(forward_chain).not_to receive(:create_or_flush)
          expect(output_chain).not_to receive(:create_or_flush)

          ingress_rule1 = double
          expect(ingress_chain).to receive(:rule)
            .with('-m state --state RELATED,ESTABLISHED -j ACCEPT')
            .and_return(ingress_rule1)
          expect(ingress_rule1).to receive(:insert_if_needed)

          ingress_rule2 = double
          expect(ingress_chain).to receive(:rule).with('-j DROP')
            .and_return(ingress_rule2)
          expect(ingress_rule2).to receive(:append_if_needed)

          egress_rule1 = double
          expect(egress_chain).to receive(:rule)
            .with('-m state --state RELATED,ESTABLISHED -j ACCEPT')
            .and_return(egress_rule1)
          expect(egress_rule1).to receive(:insert_if_needed)

          egress_rule2 = double
          expect(egress_chain).to receive(:rule)
            .with('-d 10.0.0.0/8 -j DROP')
            .and_return(egress_rule2)
          expect(egress_rule2).to receive(:append_if_needed)

          egress_rule3 = double
          expect(egress_chain).to receive(:rule)
            .with('-d 172.16.0.0/12 -j DROP')
            .and_return(egress_rule3)
          expect(egress_rule3).to receive(:append_if_needed)

          egress_rule4 = double
          expect(egress_chain).to receive(:rule)
            .with('-d 192.168.0.0/16 -j DROP')
            .and_return(egress_rule4)
          expect(egress_rule4).to receive(:append_if_needed)

          input_rule1 = double
          expect(input_chain).to receive(:rule)
            .with('-i lo -p tcp --dport 3000:3999 -j ACCEPT')
            .and_return(input_rule1)
          expect(input_rule1).to receive(:append_if_needed)

          forward_rule1 = double
          expect(forward_chain).to receive(:rule)
            .with("! -i #{bridge_tag} -o #{bridge_tag} -d 192.168.100.0/24 "\
              '-j PODBAY_INGRESS').and_return(forward_rule1)
          expect(forward_rule1).to receive(:insert_if_needed).with(1)

          forward_rule2 = double
          expect(forward_chain).to receive(:rule)
            .with("-i #{bridge_tag} ! -o #{bridge_tag} -s 192.168.100.0/24 "\
              '-j PODBAY_EGRESS').and_return(forward_rule2)
          expect(forward_rule2).to receive(:insert_if_needed).with(2)

          output_rule1 = double
          expect(output_chain).to receive(:rule)
            .with('-o lo -p tcp --dport 3000:3999 -j ACCEPT')
            .and_return(output_rule1)
          expect(output_rule1).to receive(:append_if_needed).once

          output_rule2 = double
          expect(output_chain).to receive(:rule)
            .with('-d 10.0.0.0/8 -j ACCEPT').and_return(output_rule2)
          expect(output_rule2).to receive(:append_if_needed).once

          output_rule3 = double
          expect(output_chain).to receive(:rule)
            .with('-d 172.16.0.0/12 -j ACCEPT').and_return(output_rule3)
          expect(output_rule3).to receive(:append_if_needed).once

          output_rule4 = double
          expect(output_chain).to receive(:rule)
            .with('-d 192.168.0.0/16 -j ACCEPT').and_return(output_rule4)
          expect(output_rule4).to receive(:append_if_needed).once

          subject
        end
      end # #setup_iptables

      describe '#setup_consul_server_iptables' do
        subject { daemon.setup_consul_server_iptables }

        let(:iptables) { double('iptables') }
        let(:input_chain) { double('input_chain') }

        around { |ex| Daemon::Iptables.mock(iptables) { ex.run } }

        before do
          allow(iptables).to receive(:chain).with('INPUT')
            .and_return(input_chain)
          allow(input_chain).to receive(:rule)
        end

        it 'should set up the iptables correctly' do
          input_rule1 = double
          expect(input_chain).to receive(:rule)
            .with('-p tcp --dport 7329 -j ACCEPT')
            .and_return(input_rule1)
          expect(input_rule1).to receive(:append_if_needed)
          subject
        end
      end # #setup_consul_server_iptables

      describe '#service_config', :service_config do
        subject { daemon.service_config(service_name) }
        around { |ex| Podbay::Consul::Kv.mock(mock_kv) { ex.run } }

        before do
          expect(mock_kv).to receive(:get).with('services/service-name')
            .and_return(service_def.symbolize_keys)
        end

        let(:service_name) { 'service-name' }
        let(:mock_kv) { double('mock Consul::Kv') }

        context 'with blank definition response' do
          let(:service_def) { {} }

          it 'should return default service definition' do
            is_expected.to eq(
              'size' => '0',
              'tmp_space' => "4",
              'image' => {},
              'ingress_whitelist' => [],
              'egress_whitelist' => [],
              'environment' => {}
            )
          end
        end # with empty key-value response

        context 'with valid size response' do
          let(:service_def) { { size: '5' } }
          it { is_expected.to include('size' => '5') }
        end

        context 'with valid image response' do
          let(:service_def) do
            { image: { name: 'image/name', tag: 'a528649e' } }
          end

          it 'should full image hash' do
            is_expected.to include(
              'image' => {
                'name' => 'image/name',
                'tag' => 'a528649e'
              }
            )
          end
        end # with valid image response

        context 'with single CIDR in ingress_whitelist response' do
          let(:service_def) { { ingress_whitelist: '10.0.0.0/16' } }
          it { is_expected.to include('ingress_whitelist' => ['10.0.0.0/16']) }
        end

        context 'with three CIDRs in ingress_whitelist' do
          let(:service_def) do
            { ingress_whitelist: '10.0.0.0/16,8.8.8.8/32,10.1.0.0/24' }
          end

          it 'should correctly parse CIDRs' do
            is_expected.to include(
              'ingress_whitelist' => ['10.0.0.0/16', '8.8.8.8/32',
                '10.1.0.0/24']
            )
          end
        end # with three CIDRs in ingress_whitelist

        context 'with valid egress_whitelist response' do
          let(:service_def) { { egress_whitelist: '10.0.0.0/16' } }
          it { is_expected.to include('egress_whitelist' => ['10.0.0.0/16']) }
        end

        context 'with three CIDRs in egress_whitelist' do
          let(:service_def) do
            { egress_whitelist: '10.0.0.0/16,8.8.8.8/32,10.1.0.0/24' }
          end

          it 'should correctly parse CIDRs' do
            is_expected.to include(
              'egress_whitelist' => ['10.0.0.0/16', '8.8.8.8/32',
                '10.1.0.0/24']
            )
          end
        end # with three CIDRs in egress_whitelist

        context 'with valid environment vars' do
          let(:service_def) do
            {
              environment: {
                rack_env: 'production',
                port: '8080',
                database_url: 'postgres://'
              }
            }
          end

          it 'should upcase environment vars' do
            is_expected.to include(
              'environment' => {
                'RACK_ENV' => 'production',
                'PORT' => '8080',
                'DATABASE_URL' => 'postgres://'
              }
            )
          end
        end # with valid environment vars

        context 'with size too big' do
          let(:service_def) { { size: '1234' } }

          it 'should return 0 for the size' do
            is_expected.to include('size' => '0')
          end
        end

        context 'with size containing random bytes' do
          let(:service_def) { { size: SecureRandom.random_bytes } }

          it 'should return 0 for the size' do
            is_expected.to include('size' => '0')
          end
        end

        context 'with ingress_whitelist containing random bytes' do
          let(:service_def) do
            { ingress_whitelist: SecureRandom.random_bytes(rand(64)) }
          end

          it 'should return empty array for ingress_whitelist' do
            is_expected.to include('ingress_whitelist' => [])
          end
        end

        context 'with egress_whitelist containing random bytes' do
          let(:service_def) do
            { egress_whitelist: SecureRandom.random_bytes(rand(64)) }
          end

          it 'should return empty array for egress_whitelist' do
            is_expected.to include('egress_whitelist' => [])
          end
        end

        context 'with environment containing random bytes' do
          let(:service_def) do
            { environment: SecureRandom.random_bytes(rand(64)) }
          end

          it 'should return empty hash as environment' do
            is_expected.to include('environment' => {})
          end
        end # with environment containing random bytes
      end # #service_config

      describe '#execute', :execute do
        let(:daemon_pid) { fork { daemon.execute(params) } }
        let(:params) { { config: config_file } }
        let(:server_ip) { '10.0.0.10' }

        around do |ex|
          Daemon::Process.mock(mock_process) do
            Daemon::Modules.mock(mock_modules) do
              ex.run
            end
          end
        end

        let(:mock_process) { double('mock Daemon::Process') }
        let(:mock_modules) { double('mock Daemon::Modules') }
        let(:sleep_time) { 10 }

        let(:expected_spawn) { nil }
        let(:spawn_opts) { { user: 'consul', group: 'consul' } }
        let(:dummy_spawn) { 'sleep 100' }
        let(:expected_module) { nil }
        let(:dummy_module) { nil }
        let(:setup_block) { nil }
        let(:expected_module_args) { [] }

        before do
          allow(daemon).to receive(:setup, &setup_block)

          # Catch all for spawn. Whatever needs to be tested should exit earlier
          # than 1 second. Otherwise, the exit code will be 9.
          allow(mock_process).to receive(:spawn) do
            Daemon::Process.new.spawn { sleep 1; exit 9 }
          end

          allow(mock_modules).to receive(:execute)

          if expected_module
            allow(mock_modules).to receive(:execute)
              .with(expected_module, daemon, *expected_module_args,
                &dummy_module)
          end

          # Test for a specific command being spawned. The dummy_spawn block
          # should exit with a code other than 9 so it can be distinguished from
          # the above catch all spawn. This allows for testing of the specific
          # expected_spawn command being called.
          if expected_spawn
            allow(mock_process).to receive(:spawn)
              .with(expected_spawn, spawn_opts, &dummy_spawn)
          end

          daemon_pid # Spawn daemon process
        end

        after do
          begin
            ::Process.kill('KILL', daemon_pid)
          rescue Errno::ESRCH
            # The process may have already been killed.
          end
        end

        def should_exit_with(code)
          _, status = ::Process.wait2(daemon_pid)
          expect(status.exitstatus).to eq code
        end

        context 'with basic server config file' do
          let(:config_file) { 'spec/support/daemon_configs/server.conf' }

          context 'with #setup exiting with 5' do
            let(:setup_block) { proc { exit 5 } }

            # Tests that setup is being called.
            it 'should exit with 5' do
              should_exit_with(5)
            end
          end # with #setup exiting with 5

          context 'with consul module exiting with 6' do
            let(:expected_module) { :consul }
            let(:expected_module_args) do
              [
                {
                  role: 'server',
                  cluster: 'cluster-name',
                  discovery_mode: 'awstags'
                }
              ]
            end

            let(:dummy_module) do
              proc { exit 6 }
            end

            it 'should exit with 6' do
              should_exit_with(6)
            end
          end # with consul module exiting with 6

          context 'with daemon receiving TERM signal' do
            before do
              sleep 0.1 # Give the daemon process some time to run.
              ::Process.kill('TERM', daemon_pid)
            end

            context 'with consul module never stopping' do
              let(:expected_module) { :consul }
              let(:expected_module_args) { [instance_of(Hash)] }

              let(:dummy_module) do
                proc { Daemon::Process.new.spawn('sleep 5') }
              end

              it 'should exit successfully' do
                should_exit_with(0)
              end
            end # with consul module never stopping

            context 'with consul module stopping repeatedly' do
              let(:expected_module) { :consul }
              let(:expected_module_args) { [instance_of(Hash)] }

              let(:dummy_module) do
                proc { Daemon::Process.new.spawn('sleep 0.01') }
              end

              it 'should exit successfully' do
                should_exit_with(0)
              end
            end # with consul module stopping repeatedly
          end # with daemon receiving TERM signal

          context 'with daemon receiving INT signal' do
            before do
              sleep 0.1 # Give the daemon process some time to run.
              ::Process.kill('INT', daemon_pid)
            end

            context 'with consul module never stopping' do
              let(:expected_module) { :consul }
              let(:expected_module_args) { [instance_of(Hash)] }

              let(:dummy_module) do
                proc { Daemon::Process.new.spawn('sleep 5') }
              end

              it 'should exit successfully' do
                should_exit_with(0)
              end
            end # with consul module never stopping
          end # with daemon receiving INT signal

          context 'with daemon receiving QUIT signal' do
            before do
              sleep 0.05 # Give the daemon process some time to run.
              ::Process.kill('QUIT', daemon_pid)
            end

            context 'with consul module never stopping' do
              let(:expected_module) { :consul }
              let(:expected_module_args) { [instance_of(Hash)] }

              let(:dummy_module) do
                proc { Daemon::Process.new.spawn('sleep 5') }
              end

              it 'should exit successfully' do
                should_exit_with(0)
              end
            end # with consul module never stopping
          end # with daemon receiving QUIT signal

          context 'with daemon receiving HUP signal' do
            before do
              sleep 0.05 # Give the daemon process some time to run.
              ::Process.kill('HUP', daemon_pid)
            end

            context 'with consul module never stopping' do
              let(:expected_module) { :consul }
              let(:expected_module_args) { [instance_of(Hash)] }

              let(:dummy_module) do
                proc { Daemon::Process.new.spawn('sleep 5') }
              end

              it 'should exit successfully' do
                should_exit_with(0)
              end
            end # with consul module never stopping
          end # with daemon receiving HUP signal
        end # with basic server config file

        context 'with server config file with expect = 5' do
          let(:config_file) { 'spec/support/daemon_configs/server_expt5.conf' }

          context 'with consul module receiving expect option and exiting 6' do
            let(:expected_module) { :consul }
            let(:expected_module_args) do
              [
                {
                  role: 'server',
                  cluster: 'cluster-name',
                  discovery_mode: 'awstags',
                  expect: 5
                }
              ]
            end

            let(:dummy_module) { proc { exit 6 } }

            it 'should exit with 6' do
              should_exit_with(6)
            end
          end # with consul module exiting with 6
        end # with server config file with expect = 5

        context 'with basic client config file' do
          let(:config_file) { 'spec/support/daemon_configs/client.conf' }

          context 'with executing consul module exiting 7' do
            let(:expected_module) { :consul }
            let(:expected_module_args) do
              [
                {
                  role: 'client',
                  cluster: 'cluster-name',
                  discovery_mode: 'awstags'
                }
              ]
            end

            let(:dummy_module) { proc { exit 7 } }

            it 'should exit with 7' do
              should_exit_with(7)
            end
          end # with consul module running as client

          context 'with executing registrar exiting 8' do
            let(:expected_module) { :registrar }
            let(:dummy_module) { proc { exit 8 } }

            it 'should exit with 8' do
              should_exit_with(8)
            end
          end # with executing registrar exiting 8

          context 'with executing service_router exiting 9' do
            let(:expected_module) { :service_router }
            let(:dummy_module) { proc { exit 9 } }

            it 'should exit with 9' do
              should_exit_with(9)
            end
          end # with executing service_router exiting 9
        end # with basic client config file
      end # #execute

      # Slowly migrating the above #execute tests down to this cleaner format.
      describe '#execute', :execute do
        subject { daemon.execute(params) }
        let(:params) { { config: config_file } }
        let(:daemon_pid) { fork { daemon.execute(params) } }

        let(:mock_process) { double('mock Daemon::Process') }
        let(:mock_modules) { double('mock Daemon::Modules') }

        around do |ex|
          Daemon::Process.mock(mock_process) do
            Daemon::Modules.mock(mock_modules) do
              ex.run
            end
          end
        end

        before do
          allow(daemon).to receive(:setup)
          allow(daemon).to receive(:monitor_processes)

          allow(daemon.logger).to receive(:info)
        end

        after do
          subject

          begin
            ::Process.kill('KILL', daemon_pid)
          rescue Errno::ESRCH
            # The process may have already been killed.
          end
        end

        context 'with basic client config file' do
          let(:config_file) { 'spec/support/daemon_configs/client.conf' }
          let(:module_process) { double('module process') }

          before do
            allow(mock_modules).to receive(:execute)
              .and_return(module_process)
          end

          it 'should execute consul module' do
            expect(mock_modules).to receive(:execute)
              .with(:consul, daemon,
                role: 'client',
                cluster: 'cluster-name',
                discovery_mode: 'awstags'
              ).once
          end

          it 'should execute registrar' do
            expect(mock_modules).to receive(:execute)
              .with(:registrar, daemon)
          end

          it 'should execute service_router' do
            expect(mock_modules).to receive(:execute)
              .with(:service_router, daemon)
          end

          it 'should execute garbage_collector' do
            expect(mock_modules).to receive(:execute)
              .with(:garbage_collector, daemon)
          end

          it 'should pass module processes to monitor_processes' do
            expect(daemon).to receive(:monitor_processes)
              .with([module_process] * 4).once
          end

          context 'with daemon receiving USR1 signal' do
            before do
              sleep 0.05 # Give the daemon process some time to run.
              ::Process.kill('USR1', daemon_pid)
            end

            it 'should reinitialize logger' do
              expect(daemon).to receive(:reinitialize_logger).once
            end
          end # with daemon receiving USR1 signal

          context 'with registrar returning nil process' do
            before do
              allow(mock_modules).to receive(:execute).with(:registrar, daemon)
                .and_return(nil)
            end

            it 'should not pass nil to #monitor_processes' do
              # Only three module processes: consul, service_router and
              # garbage_collector, since registrar returned nil.
              expect(daemon).to receive(:monitor_processes)
                .with([module_process] * 3).once
            end
          end # with nil module process
        end # with basic client config file
      end # #execute

      describe '#launch', :launch do
        subject { daemon.launch(service_name) }

        let(:podbay_image_tars_path) { '/var/podbay/image_tars' }
        let(:mock_utils) { double('Podbay::Utils') }
        let(:mock_s3_utils) { double('Podbay::Utils::S3') }
        let(:mock_s3_file) { double('Podbay::Utils::S3File') }
        let(:iptables) { double('Podbay::Daemon::Iptables') }
        let(:mock_docker) { double('Podbay::Docker') }
        let(:mock_container_info) { double('Podbay::Daemon::ContainerInfo') }

        let(:mock_loop_devices) do
          double('mock Podbay::Componenets::Daemon::LoopDevices')
        end

        let(:service_name) { 'service-name' }
        let(:service_conf) do
          {
            'size' => size,
            'tmp_space' => tmp_space,
            'image' => image,
            'ingress_whitelist' => ingress_whitelist,
            'egress_whitelist' => egress_whitelist,
            'environment' => environment
          }
        end

        let(:size) { '0' }
        let(:tmp_space) { '4' }
        let(:image) { {'name' => 'image/name', 'tag' => 'abcdefghijklmnop'} }
        let(:image_name) { "#{image['name']}:#{image['tag']}" }
        let(:ingress_whitelist) { [] }
        let(:egress_whitelist) { [] }
        let(:environment) { {} }
        let(:docker_net_resp) { docker_net_resp_with_containers }
        let(:taken_ports) { [1234, 22, 8080, 3001, 3003, 3004, 3005] }
        let(:tmp_mount_path) { '/var/podbay/mounts/1234abcd' }
        let(:container_id) { SecureRandom.hex(32) }

        #around { |ex| Daemon::Iptables.mock(iptables) { ex.run } }

        around do |ex|
          Utils.mock(mock_utils) do
            Daemon::ContainerInfo.mock(mock_container_info) do
              Daemon::Iptables.mock(iptables) do
                Daemon::LoopDevices.mock(mock_loop_devices) do
                  Podbay::Docker.mock(mock_docker) do
                    Podbay::Utils::S3File.mock(mock_s3_file) do
                      Podbay::Utils::S3.mock(mock_s3_utils) do
                        ex.run
                      end
                    end
                  end
                end
              end
            end
          end
        end

        before do
          # Mock needed external calls.
          allow(daemon).to receive(:service_config).with(service_name)
            .and_return(service_conf)

          allow(daemon).to receive(:`).with('docker network inspect '\
            'br-podbay 2> /dev/null')
            .and_return(docker_net_resp)

          allow(daemon).to receive(:`).with("netstat -vatn | tr -s ' ' | " \
            "cut -d ' ' -f 4 | tail -n +3 | tr -s ':' | cut -d ':' -f 2 | " \
            "sort | uniq").and_return("#{taken_ports.join("\n")}")

          # Setup base iptables mock.
          allow(iptables).to receive(:chain)
            .and_return(
              double('chain',
                create_or_flush: nil,
                rule: double('rule',
                  append: nil,
                  insert_if_needed: nil
                )
              )
            )

          # For the loop device call:
          allow(mock_loop_devices).to receive(:create).with(4194304, '4000')
            .and_return(tmp_mount_path)

          # For the docker call:
          allow(mock_utils).to receive(:system)
            .with(
              instance_of(Hash),
              a_string_starting_with('docker run'),
              instance_of(Hash)
            )
            .and_return([container_id, docker_run_success])

          allow(mock_container_info).to receive(:write_service_name)

          allow(mock_docker).to receive(:pull).and_return(docker_pull_success)
          allow(mock_docker).to receive(:load).and_return(docker_load_success)

          allow(mock_s3_file).to receive(:new).and_return(s3_file_instance)
          allow(s3_file_instance).to receive(:read).and_return(s3_file_contents)

          allow(mock_s3_utils).to receive(:object_exists?)
            .and_return(s3_object_exists)

          allow(mock_utils).to receive(:create_directory_path)
          allow(mock_utils).to receive(:gunzip_file)
          allow(mock_utils).to receive(:valid_sha256?).and_return(sha256_valid)

          allow(File).to receive(:open).and_yield(mock_file_handle)
          allow(mock_file_handle).to receive(:write)
          allow(mock_utils).to receive(:rm)
        end

        let(:docker_run_success) { true }
        let(:docker_pull_success) { true }
        let(:docker_load_success) { true }
        let(:s3_object_exists) { true }
        let(:s3_file_instance) { double('S3File instance') }
        let(:s3_file_contents) { '12345' }
        let(:mock_file_handle) { double('file handle') }
        let(:sha256_valid) { true }

        after { subject rescue nil }

        def expect_PODBAY_INGRESS_to_be_setup_correctly(ip)
          chain = double('ingress_chain')
          expect(iptables).to receive(:chain).with('PODBAY_INGRESS')
            .and_return(chain)
          expect(chain).not_to receive(:flush) # would be bad!
          expect(chain).not_to receive(:create_or_flush) # would be bad!

          rule = double('podbay ingress rule')
          expect(chain).to receive(:rule).with("-d #{ip} -g IP_#{ip}_INGRESS")
            .and_return(rule)
          expect(rule).to receive(:insert_if_needed).with(2).once
        end

        def expect_PODBAY_EGRESS_to_be_setup_correctly(ip)
          chain = double('egress_chain')
          expect(iptables).to receive(:chain).with('PODBAY_EGRESS')
            .and_return(chain)
          expect(chain).not_to receive(:flush) # would be bad!
          expect(chain).not_to receive(:create_if_needed)

          rule = double('podbay egress rule')
          expect(chain).to receive(:rule).with("-s #{ip} -j IP_#{ip}_EGRESS")
            .and_return(rule)
          expect(rule).to receive(:insert_if_needed).with(2).once
        end

        def expect_container_ingress_to_be_setup_correctly(ip)
          chain = double('container_ingress_chain')
          expect(iptables).to receive(:chain).with("IP_#{ip}_INGRESS")
            .and_return(chain)
          expect(chain).to receive(:create_or_flush).once

          ingress_whitelist.each_with_index do |cidr, index|
            rule = double("container ingress rule #{index}")
            expect(chain).to receive(:rule)
              .with("-s #{cidr} -j RETURN").and_return(rule)
            expect(rule).to receive(:append).once
          end

          final_rule = double('container ingress final rule')
          expect(chain).to receive(:rule)
            .with('-j DROP').and_return(final_rule)
          expect(final_rule).to receive(:append).once
        end

        def expect_container_egress_to_be_setup_correctly(ip)
          chain = double('container_egress_chain')
          expect(iptables).to receive(:chain).with("IP_#{ip}_EGRESS")
            .and_return(chain)
          expect(chain).to receive(:create_or_flush).once

          egress_whitelist.each_with_index do |cidr, index|
            rule = double("container egress rule #{index}")
            expect(chain).to receive(:rule)
              .with("-d #{cidr} -j ACCEPT").and_return(rule)
            expect(rule).to receive(:append).once
          end
        end

        def expect_system(env, command = nil)
          unless command
            command = env
            env = instance_of(Hash)
          end

          expect(mock_utils).to receive(:system)
            .with(env, command, unsetenv_others: true).once
        end

        context 'with a image.src config' do
          before { image.merge!('src' => 's3://bucket') }

          let(:image_uri) do
            URI("#{image['src']}/#{image['name']}/#{image['tag']}")
          end

          let(:bucket_name) { image_uri.host }
          let(:object_path) { image_uri.path.gsub(/\A\//, '') }

          context 'with image existing in s3' do
            let(:s3_object_exists) { true }
            let(:image_dir) { "#{podbay_image_tars_path}/#{image['name']}" }
            let(:image_tar) { "#{image_dir}/#{image['tag']}" }

            it 'should pull and gunzip the tar from s3 and no sha256 defined' do
              expect(mock_utils).to receive(:create_directory_path)
                .with(image_dir).once
              expect(mock_s3_file).to receive(:new)
                .with(image_uri.to_s).once
              expect(File).to receive(:open)
                .with(image_tar, 'w').and_yield(mock_file_handle)
              expect(mock_file_handle).to receive(:write).with('12345')
              expect(mock_utils).to receive(:gunzip_file).with(image_tar)
            end

            context 'with a sha256 defined' do
              before do
                image.merge!('sha256' => 'df1a287a77397c45f706ce43d7ebfa' \
                  'e39c900f6829d61f860461ed354f3f7bdd')
              end

              it 'should check the sha256 is valid' do
                expect(mock_utils).to receive(:valid_sha256?)
                  .with(image_tar, 'df1a287a77397c45f706ce43d7ebfa' \
                    'e39c900f6829d61f860461ed354f3f7bdd')
              end

              context 'with sha256 defined valid' do
                let(:sha256_valid) { true }

                context 'with a non-corrupt docker image tar' do
                  let(:docker_load_success) { true }

                  it 'should docker load the image' do
                    expect(mock_docker).to receive(:load)
                    .with(image_tar).once
                  end
                end # with a non-corrupt docker image tar

                context 'with a corrupt docker image tar' do
                  let(:docker_load_success) { false }

                  it 'should raise expected error' do
                    expect { subject }
                      .to raise_error Podbay::ImageRetrieveError, "Failed " \
                        "to load #{image_tar}"
                  end
                end # with a corrupt docker image tar
              end # with sha256 defined valid

              context 'with sha256 defined invalid' do
                let(:sha256_valid) { false }

                it 'should raise expected error' do
                  expect { subject }.to raise_error Podbay::ImageRetrieveError,
                  "Invalid sha256 for #{image_uri.to_s}: " \
                    "expected #{image['sha256']}"
                end
              end # with sha256 defined invalid
            end # with a sha256 defined

            context 'with successful docker run' do
              let(:docker_run_success) { true }

              it 'should delete image' do
                expect(mock_utils).to receive(:rm).with(image_tar).once
              end
            end

            context 'with unsuccessful docker run' do
              let(:docker_run_success) { false }

              it 'should not delete image' do
                expect(mock_utils).not_to receive(:rm).with(image_tar)
              end
            end
          end # with image existing in s3

          context 'with image not existing in s3' do
            let(:s3_object_exists) { false }
            it 'should raise expected error' do
              expect { subject }.to raise_error Podbay::ImageRetrieveError,
              "Object #{object_path} does not exist in #{bucket_name} bucket"
            end
          end # with image not existing in s3
        end # with a image.src config

        context 'with no image.src defined' do
          it 'should pull the Docker image' do
            expect(mock_docker).to receive(:pull)
              .with(image['name'], image['tag']).once
          end

          it 'should not call Utils.rm' do
            expect(mock_utils).not_to receive(:rm)
          end
        end # with no image.src defined'

        context 'with no other containers running' do
          let(:container_ips) { [] }
          let(:taken_ports) { [22, 8080] } # No container ports taken.

          context 'with ingress_whitelist empty' do
            let(:ingress_whitelist) { [] }

            it 'should setup IP_192.168.100.2_INGRESS correctly' do
              expect_container_ingress_to_be_setup_correctly('192.168.100.2')
            end

            it 'should setup PODBAY_INGRESS correctly' do
              expect_PODBAY_INGRESS_to_be_setup_correctly('192.168.100.2')
            end
          end # with ingress_whitelist empty

          context 'with ingress_whitelist containing two IPs' do
            let(:ingress_whitelist) { ['10.0.0.5/32', '10.0.0.7/32'] }

            it 'should setup IP_192.168.100.2_INGRESS correctly' do
              expect_container_ingress_to_be_setup_correctly('192.168.100.2')
            end

            it 'should setup PODBAY_INGRESS correctly' do
              expect_PODBAY_INGRESS_to_be_setup_correctly('192.168.100.2')
            end
          end # with ingress_whitelist containing two IPs

          context 'with egress_whitelist empty' do
            let(:egress_whitelist) { [] }

            it 'should setup IP_192.168.100.2_EGRESS correctly' do
              expect_container_egress_to_be_setup_correctly('192.168.100.2')
            end

            it 'should setup PODBAY_EGRESS correctly' do
              expect_PODBAY_EGRESS_to_be_setup_correctly('192.168.100.2')
            end
          end # with egress_whitelist containing two IPs

          context 'with egress_whitelist containing two IPs' do
            let(:egress_whitelist) { ['10.0.0.8/32', '10.0.0.10/32'] }

            it 'should setup IP_192.168.100.2_EGRESS correctly' do
              expect_container_egress_to_be_setup_correctly('192.168.100.2')
            end

            it 'should setup PODBAY_EGRESS correctly' do
              expect_PODBAY_EGRESS_to_be_setup_correctly('192.168.100.2')
            end
          end # with egress_whitelist containing two IPs

          context 'with empty environment' do
            let(:environment) { {} }

            it 'should call docker run with expected arguments' do
              expect_system(
                {'PORT' => '3000'},
                'docker run -d --net br-podbay --ip 192.168.100.2 ' \
                '-p 3001:3000 -e PORT -v /dev/log:/dev/log ' \
                '-v /etc/podbay/hosts:/etc/hosts:ro --read-only ' \
                "-v #{tmp_mount_path}:/tmp -v #{tmp_mount_path}:/app/tmp " \
                '--tmpfs /run:size=128k --log-driver=syslog ' \
                "--log-opt tag=\"#{service_name}\" --memory-swappiness=\"0\" " \
                "--memory=\"16m\" --cpu-shares=\"16\" " \
                "--restart=\"unless-stopped\" #{image_name}"
              )
            end
          end # with empty environment

          context 'with environment containing PORT' do
            let(:environment) { { 'PORT' => '8080' } }

            it 'should should use the specified PORT as the container port' do
              expect_system(environment, a_string_including('-p 3001:8080'))
            end

            it 'should should expose PORT env to container' do
              expect_system(environment, a_string_including('-e PORT'))
            end
          end # with environment containing PORT

          context 'with environment not containing PORT' do
            let(:environment) { {} }

            it 'should use 3000 as the container port' do
              expect_system(
                {'PORT' => '3000'},
                a_string_including('-p 3001:3000')
              )
            end

            it 'should should expose PORT env to container' do
              expect_system({'PORT' => '3000'}, a_string_including('-e PORT'))
            end
          end # with environment not containing PORT

          context 'with environment containing three keys' do
            let(:environment) do
              {
                'RACK_ENV' => 'production',
                'PORT' => '1234',
                'DATABASE_URL' => 'postgres://'
              }
            end

            it 'should expose container to all environment keys' do
              expect_system(
                environment,
                a_string_including('-e DATABASE_URL -e PORT -e RACK_ENV')
              )
            end
          end # with environment containing three keys

          context 'with size = 1' do
            let(:size) { '1' }

            it 'should limit memory to 32m' do
              expect_system(a_string_including('--memory="32m"'))
            end

            it 'should set cpu-shares to 32' do
              expect_system(a_string_including('--cpu-shares="32"'))
            end
          end # with size = 1

          context 'with size = 5' do
            let(:size) { '5' }

            it 'should limit memory to 512m' do
              expect_system(a_string_including('--memory="512m"'))
            end

            it 'should set cpu-shares to 512' do
              expect_system(a_string_including('--cpu-shares="512"'))
            end
          end # with size = 5

          context 'with size = 9' do
            let(:size) { '9' }

            it 'should limit memory to 8192m' do
              expect_system(a_string_including('--memory="8192m"'))
            end

            it 'should set cpu-shares to 8192' do
              expect_system(a_string_including('--cpu-shares="8192"'))
            end
          end # with size = 9
        end # with no other containers running

        context 'with other containers running on .2, .3 and .5' do
          let(:container_ips) do
            ['192.168.100.2/24', '192.168.100.3/24', '192.168.100.5/24']
          end

          it 'should setup IP_192.168.100.4_INGRESS correctly' do
            expect_container_ingress_to_be_setup_correctly('192.168.100.4')
          end

          it 'should setup IP_192.168.100.4_EGRESS correctly' do
            expect_container_egress_to_be_setup_correctly('192.168.100.4')
          end

          it 'should setup PODBAY_INGRESS correctly' do
            expect_PODBAY_INGRESS_to_be_setup_correctly('192.168.100.4')
          end

          it 'should setup PODBAY_EGRESS correctly' do
            expect_PODBAY_EGRESS_to_be_setup_correctly('192.168.100.4')
          end

          it 'should should run container on 192.168.100.4' do
            expect_system(
              {'PORT' => '3000'},
              a_string_including('--ip 192.168.100.4')
            )
          end
        end # with other containers running on .2, .3 and .5

        context 'with containers using ports 3001, 3002, 3003, 3005, 3006' do
          let(:taken_ports) { [22, 8080, 3001, 3002, 3003, 3005, 3006] }

          it 'should should bind container to 3004' do
            expect_system(
              {'PORT' => '3000'},
              a_string_including('-p 3004:3000')
            )
          end
        end # with containers using ports 3001, 3002, 3003, 3005, 3006

        context 'with docker run returning container_id' do
          let(:container_id) { SecureRandom.hex(32) }

          it 'should record service name for container' do
            expect(mock_container_info).to receive(:write_service_name)
              .with(container_id, service_name).once
          end
        end

        context 'with docker run returning unexpected response' do
          let(:container_id) { 'What is this thing?' }

          it 'should log raise_error' do
            expect(daemon.logger).to receive(:error)
              .with('Received unexpected output when launching ' \
                "#{service_name}: \"What is this thing?\""
              ).once
          end
        end
      end # #launch
    end # Daemon
  end # Components
end # Podbay
