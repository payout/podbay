require 'securerandom'

module Podbay::Components
  class Daemon::Modules
    RSpec.describe Registrar do
      let(:daemon) { Daemon.new }
      let(:registrar) { Registrar.new(daemon) }

      describe '#execute', :execute do
        subject { registrar.execute(on_or_off, events_store_max) }

        let(:mock_process) { double('Daemon::Process') }
        let(:mock_docker) { double('Docker') }
        let(:process) { double('Daemon::Process instance') }
        let(:docker_event) { double('docker event') }
        let(:docker_event0) { double('docker event') }
        let(:docker_event1) { double('docker event') }
        let(:docker_event2) { double('docker event') }
        let(:event_name) { nil }
        let(:container_id) { SecureRandom.hex(32) }
        let(:event_time) { 0 }
        let(:on_or_off) { 'on' }
        let(:events_store_max) { 1000 }

        around do |ex|
          Daemon::Process.mock(mock_process) do
            Podbay::Docker.mock(mock_docker) do
              ex.run
            end
          end
        end

        before do
          allow(mock_process).to receive(:spawn).and_yield.and_return(process)
          allow(registrar).to receive(:wait_for_consul)
          allow(registrar).to receive(:wait_for_docker)
          allow(registrar).to receive(:register_running_containers)
          allow(registrar).to receive(:loop).and_yield
          allow(mock_docker).to receive(:stream_events).and_yield(docker_event)
          allow(docker_event).to receive(:status).and_return(event_name)
          allow(docker_event).to receive(:id).and_return(container_id)
          allow(docker_event).to receive(:time).and_return(event_time)

          allow(mock_docker).to receive(:stream_events).and_yield(docker_event0)
          allow(docker_event0).to receive(:status).and_return(event_name)
          allow(docker_event0).to receive(:id).and_return(container_id)
          allow(docker_event0).to receive(:time).and_return(0)

          allow(mock_docker).to receive(:stream_events).and_yield(docker_event1)
          allow(docker_event1).to receive(:status).and_return(event_name)
          allow(docker_event1).to receive(:id).and_return(container_id)
          allow(docker_event1).to receive(:time).and_return(1)

          allow(mock_docker).to receive(:stream_events).and_yield(docker_event2)
          allow(docker_event2).to receive(:status).and_return(event_name)
          allow(docker_event2).to receive(:id).and_return(container_id)
          allow(docker_event2).to receive(:time).and_return(2)

          allow(registrar).to receive(:register)
          allow(registrar).to receive(:deregister)
        end

        after { subject }

        context 'with on_or_off = "on"' do
          let(:on_or_off) { 'on' }

          it 'should return process' do
            is_expected.to eq process
          end

          it 'should wait for consul' do
            expect(registrar).to receive(:wait_for_consul).once
          end

          it 'should wait for docker' do
            expect(registrar).to receive(:wait_for_docker).once
          end

          it 'should call #register_running_containers' do
            expect(registrar).to receive(:register_running_containers).once
          end

          context 'with start event' do
            let(:event_name) { 'start' }

            it 'should register' do
              expect(registrar).to receive(:register).with(container_id).once
            end

            it 'should not deregister' do
              expect(registrar).not_to receive(:deregister)
            end
          end

          context 'with start event that has been seen before' do
            before do
              allow(mock_docker).to receive(:stream_events)
                .and_yield(docker_event).and_yield(docker_event)
            end

            let(:event_name) { 'start' }
            let(:container_id) do
              'c292871f31e1a87b90294b584b02331c' \
              '52131152d81e1bed249808935ed9007e'
            end

            it 'should only register it once' do
              expect(registrar).to receive(:register).once
            end
          end # with start event that has been seen before

          context 'with 3 start events that are unique' do
            before do
              allow(mock_docker).to receive(:stream_events)
                .and_yield(docker_event0).and_yield(docker_event1)
                  .and_yield(docker_event2)
            end

            let(:event_name) { 'start' }
            let(:container_id) do
              'c292871f31e1a87b90294b584b02331c' \
              '52131152d81e1bed249808935ed9007e'
            end

            it 'should register' do
              expect(registrar).to receive(:register).exactly(3).times
            end
          end # with 3 start events that are unique

          context 'with multiple events' do
            before do
              allow(mock_docker).to receive(:stream_events)
                .and_yield(docker_event0).and_yield(docker_event1)
                  .and_yield(docker_event2).and_yield(docker_event0)
            end

            let(:events_store_max) { 2 }
            let(:event_name) { 'start' }
            let(:container_id) do
              'c292871f31e1a87b90294b584b02331c' \
              '52131152d81e1bed249808935ed9007e'
            end

            it 'it should shift the store and register the repeated event' do
              expect(registrar).to receive(:register).exactly(4).times
            end
          end # 'with multiple events it should be shifting the store'

          context 'with die event' do
            let(:event_name) { 'die' }

            it 'should not register' do
              expect(registrar).not_to receive(:register)
            end

            it 'should deregister' do
              expect(registrar).to receive(:deregister).with(container_id).once
            end
          end # with die event

          context 'with stop event' do
            let(:event_name) { 'stop' }

            it 'should not register' do
              expect(registrar).not_to receive(:register)
            end

            it 'should not deregister' do
              expect(registrar).not_to receive(:deregister)
            end
          end
        end # with on_or_off = "on"

        context 'with on_or_off = "off"' do
          let(:on_or_off) { 'off' }
          it { is_expected.to be nil }

          it 'should not spawn process' do
            expect(mock_process).not_to receive(:spawn)
          end
        end # with on_or_off = "off"

        context 'with on_or_off = nil' do
          let(:on_or_off) { nil }

          it 'should return process' do
            is_expected.to eq process
          end

          it 'should not spawn process' do
            expect(mock_process).to receive(:spawn)
          end
        end # with on_or_off = "off"
      end # #execute

      describe '#register', :register do
        subject { registrar.register(container_id) }

        around do |ex|
          Daemon::ContainerInfo.mock(mock_container_info) do
            Podbay::Docker.mock(docker_mock) do
              Podbay::Consul.mock(consul_mock) do
                ex.run
              end
            end
          end
        end

        let(:mock_container_info) { double('Daemon::ContainerInfo') }
        let(:docker_mock) { double('Podbay::Docker') }
        let(:consul_mock) { double('Podbay::Consul') }
        let(:container_id) { '5faf5161d528' }
        let(:consul_registration_resp) { true } # success or failure
        let(:get_service_definition_resp) { {test: 'non_empty_hash'} }
        let(:container_status) { 'running' }
        let(:container_image) { "#{service_name}:tag" }
        let(:service_name) { 'service-name' }
        let(:host_ports) { { container_port.to_s => [host_port.to_s] } }
        let(:container_port) { 3000 }
        let(:host_port) { 3001 }
        let(:service_id) { container_id }
        let(:service_check) { {} }

        let(:container_info) do
          {
            'Id' => container_id,
            'State' => {
              'Status' => container_status
            },
            'Config' => {
              'Image' => container_image
            },
            'HostConfig' => {
              'PortBindings' => Hash[
                host_ports.map do |container_port, hport|
                  [
                    "#{container_port}/tcp",
                    hport.map { |port| { 'HostIp' => '', 'HostPort' => port } }
                  ]
                end
              ]
            }
          }
        end

        def is_expected_to_register(hash)
          expect(consul_mock).to receive(:register_service)
            .with(hash_including(hash)).once
          subject
        end

        before do
          allow(docker_mock).to receive(:inspect_container).with(container_id)
            .and_return(container_info)
          allow(mock_container_info).to receive(:service_name)
            .with(container_id).and_return(service_name)
          allow(consul_mock).to receive(:get_service_check).with(service_name)
            .and_return(service_check)
          allow(consul_mock).to receive(:register_service)
            .and_return(consul_registration_resp)
          allow(consul_mock).to receive(:get_service_definition)
            .with(service_name).and_return(get_service_definition_resp)
        end


        it 'should get container details from docker' do
          expect(docker_mock).to receive(:inspect_container)
            .with(container_id).once
          subject
        end

        it 'should get service definition' do
          expect(consul_mock).to receive(:get_service_definition).once
          subject
        end

        it 'should get service name' do
          expect(mock_container_info).to receive(:service_name)
            .with(container_id).once
          subject
        end

        it 'should register service with consul' do
          expect(consul_mock).to receive(:register_service).once
          subject
        end

        it 'should register service name correctly' do
          is_expected_to_register('Name' => service_name)
        end

        it 'should register service ID correctly' do
          is_expected_to_register('ID' => service_id)
        end

        it 'should register address correctly' do
          is_expected_to_register(
            'Address' => a_string_matching(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/)
          )
        end

        context 'with service name not in Consul' do
          let(:get_service_definition_resp) { {} }
          it 'should not register service with consul' do
            expect(consul_mock).not_to receive(:register_service)
            subject
          end
        end

        context 'with no ports' do
          let(:host_ports) { {} }

          it 'should not register a port' do
            expect(consul_mock).to receive(:register_service)
              .with(
                'ID' => service_id,
                'Name' => service_name,
                'Address' => String
              ).once
            subject
          end
        end # with no ports

        context 'with host port 3001' do
          let(:host_port) { 3001 }

          it 'should register port correctly with consul' do
            is_expected_to_register('Port' => host_port)
          end
        end # with host port 3001

        context 'with host port 3007' do
          let(:host_port) { 3007 }

          it 'should register port correctly with consul' do
            is_expected_to_register('Port' => host_port)
          end
        end # with host port 3007

        context 'with HTTP service check with interval' do
          let(:service_check) do
            {
              'HTTP' => '/health',
              'Interval' => '10s'
            }
          end

          context 'without host port' do
            let(:host_ports) { {} }

            it 'should raise error' do
              expect { subject }.to raise_error "can't define http check if " \
                "no port is bound"
            end
          end

          context 'with host port 3001' do
            let(:host_port) { 3001 }

            it 'should register health check for port 3001' do
              is_expected_to_register(
                'Check' => {
                  'HTTP' => 'http://localhost:3001/health',
                  'Interval' => '10s'
                }
              )
            end
          end # with host port 3001

          context 'with host port 3007' do
            let(:host_port) { 3007 }

            it 'should register health check for port 3007' do
              is_expected_to_register(
                'Check' => {
                  'HTTP' => 'http://localhost:3007/health',
                  'Interval' => '10s'
                }
              )
            end
          end # with host port 3007
        end # with HTTP service check

        context 'with HTTP service check with no interval' do
          let(:host_port) { 3001 }
          let(:service_check) do
            {
              'HTTP' => '/health'
            }
          end

          it 'should register a HTTP check with default interval' do
            is_expected_to_register(
              'Check' => {
                'HTTP' => 'http://localhost:3001/health',
                'Interval' => '30s'
              }
            )
          end
        end # with HTTP service check with no interval

        context 'with TCP service check with interval' do
          let(:host_port) { 3001 }
          let(:service_check) do
            {
              'TCP' => 'true',
              'Interval' => '10s'
            }
          end

          it 'should register a TCP check with same interval' do
            is_expected_to_register(
              'Check' => {
                'TCP' => 'localhost:3001',
                'Interval' => '10s'
              }
            )
          end

          context 'with no port' do
            let(:host_ports) { {} }

            it 'should raise error' do
              expect { subject }.to raise_error "can't define tcp check" \
               " if no port is bound"
            end
          end
        end # with TCP service check with interval

        context 'with TCP service check with no interval' do
          let(:host_port) { 3001 }
          let(:service_check) do
            {
              'TCP' => 'true'
            }
          end

          it 'should register a TCP check with default interval' do
            is_expected_to_register(
              'Check' => {
                'TCP' => 'localhost:3001',
                'Interval' => '30s'
              }
            )
          end
        end # with TCP service check with no interval

        context 'with script service check with interval' do
          let(:service_check) do
            {
              'Script' => './test_health',
              'Interval' => '10s'
            }
          end

          it 'should register a script check with same interval' do
            is_expected_to_register(
              'Check' => {
                'Script' => './test_health',
                'Interval' => '10s'
              }
            )
          end
        end # with script service check with interval

        context 'with script service check without interval' do
          let(:service_check) do
            {
              'Script' => './test_health'
            }
          end

          it 'should register a script check with default interval' do
            is_expected_to_register(
              'Check' => {
                'Script' => './test_health',
                'Interval' => '30s'
              }
            )
          end
        end # with script service check with interval

        context 'with TTL service check' do
          let(:service_check) do
            {
              'TTL' => '15s'
            }
          end

          it 'should register a TTL check' do
            is_expected_to_register(
              'Check' => {
                'TTL' => '15s'
              }
            )
          end
        end # with TTL service check

        context 'with TTL service check with interval' do
          let(:service_check) do
            {
              'TTL' => '15s',
              'Interval' => '30s'
            }
          end

          it 'should register a TTL check with interval ignored' do
            is_expected_to_register(
              'Check' => {
                'TTL' => '15s'
              }
            )
          end
        end # with TTL service check with interval

        context 'with all service checks' do
          let(:host_port) { 3001 }
          let(:service_check) do
            {
              'HTTP' => '/health',
              'TCP' => 'true',
              'Script' => './test_health',
              'TTL' => '15s'
            }
          end

          it 'should register just the HTTP check' do
            is_expected_to_register(
              'Check' => {
                'HTTP' => 'http://localhost:3001/health',
                'Interval' => '30s'
              }
            )
          end
        end # with all service checks

        context 'with TCP, script and TTL checks' do
          let(:host_port) { 3001 }
          let(:service_check) do
            {
              'TCP' => 'true',
              'Script' => './test_health',
              'TTL' => '15s'
            }
          end

          it 'should register just the HTTP check' do
            is_expected_to_register(
              'Check' => {
                'TCP' => 'localhost:3001',
                'Interval' => '30s'
              }
            )
          end
        end # with TCP, script and TTL checks

        context 'with script and TTL checks' do
          let(:host_port) { 3001 }
          let(:service_check) do
            {
              'Script' => './test_health',
              'TTL' => '15s'
            }
          end

          it 'should register just the HTTP check' do
            is_expected_to_register(
              'Check' => {
                'Script' => './test_health',
                'Interval' => '30s'
              }
            )
          end
        end # with script and TTL checks

        context 'with container status created' do
          let(:container_status) { 'created' }

          it 'should raise error' do
            expect(daemon.logger).to receive(:warn).with(
              "Skipping registration for #{container_id} because it is created")
              .once
            subject
          end
        end

        context 'with service name returned as nil' do
          let(:service_name) { nil }

          it 'should raise error' do
            expect { subject }.to raise_error('could not determine service ' \
              "name for #{container_id}")
          end
        end

        context 'with nil container info' do
          after { subject }

          let(:container_info) { nil }

          it 'should log error' do
            expect(daemon.logger).to receive(:error).with('Could not register '\
              "#{container_id} because it does not exist.").once
          end
        end # with nil container info
      end # #register

      describe '#register_running_containers', :register_running_containers do
        subject { registrar.register_running_containers }
        let(:mock_docker) { double('Podbay::Docker') }

        around do |ex|
          Podbay::Docker.mock(mock_docker) do
            ex.run
          end
        end

        before do
          allow(mock_docker).to receive(:containers)
            .and_return(running_containers)
        end

        after { subject }

        context 'with no containers running' do
          let(:running_containers) { [] }

          it 'should not call #register' do
            expect(registrar).not_to receive(:register)
          end
        end

        context 'with two containers running' do
          let(:running_containers) { [{'id' => 'one'},{'id' => 'two'}] }

          it 'should register both containers' do
            expect(registrar).to receive(:register).with('one').once
            expect(registrar).to receive(:register).with('two').once
          end
        end
      end # #register_running_containers

      describe '#deregister', :deregister do
        subject { registrar.deregister(container_id) }
        let(:container_id) { '5faf5161d528' }
        let(:consul_mock) { double('Podbay::Consul') }

        around do |ex|
          Podbay::Consul.mock(consul_mock) do
            ex.run
          end
        end

        after { subject }

        it 'should call Consul.deregister_local_service' do
          expect(consul_mock).to receive(:deregister_local_service)
            .with(container_id).once
        end
      end # deregister
    end # Registrar
  end # Daemon::Modules
end # Podbay::Components
