require 'base64'
require 'securerandom'

module Podbay::Components
  class Daemon::Modules
    RSpec.describe StaticServices do
      let(:daemon) { Daemon.new }
      let(:static_services) { StaticServices.new(daemon) }

      describe '#execute' do
        subject { static_services.execute(*services) }
        let(:pid) { subject.pid }
        let(:services) { [] }

        def should_exit_with(code)
          _, status = ::Process.wait2(pid)
          expect(status.exitstatus).to eq code
        end

        let(:mock_docker) { double('mock Podbay::Docker') }

        around do |ex|
          Podbay::Docker.mock(mock_docker) do
            ex.run
          end
        end

        before do
          allow(static_services).to receive(:wait_for_event)
            .with(:service_router_ready)

          allow(daemon).to receive(:launch)
          allow(mock_docker).to receive(:containers).and_return(containers)
          allow(static_services).to receive(:handle_events) { sleep 10 }
        end

        after do
          begin
            ::Process.kill('TERM', pid)
          rescue Errno::ESRCH
            # Process may have already exited.
          end
        end

        let(:containers) { [] }

        it 'should wait for service_router_ready event' do
          allow(static_services).to receive(:wait_for_event)
            .with(:service_router_ready) { exit 5 }
          should_exit_with(5)
        end

        it 'should call #handle_events' do
          allow(static_services).to receive(:handle_events)
            .with(no_args) { exit 3 }
          should_exit_with(3)
        end

        context 'with two services specified' do
          let(:services) { ['service1', 'service2'] }
          before { allow(daemon).to receive(:launch) }

          context 'with no services running' do
            let(:containers) { [] }

            it 'should launch service1' do
              allow(daemon).to receive(:launch).with('service1') { exit 6 }
              should_exit_with(6)
            end

            it 'should launch service2' do
              allow(daemon).to receive(:launch).with('service2') { exit 7 }
              should_exit_with(7)
            end
          end # with no services running

          context 'with service1 running already' do
            let(:containers) { [{'Image' => 'service1:tag'}] }

            it 'should not launch service1' do
              expect(daemon).not_to receive(:launch).with('service1')
              sleep(0.1) # Wait for process to do stuff.
              ::Process.kill('TERM', pid)
              should_exit_with(0) # It will exit with 1 if the expect fails.
            end

            it 'should launch service2' do
              allow(daemon).to receive(:launch).with('service2') { exit 8 }
              should_exit_with(8)
            end
          end # with service1 running already

          context 'with both services already running' do
            let(:containers) do
              [{'Image' => 'service1:tag'}, {'Image' => 'service2:tag'}]
            end

            it 'should not launch any services' do
              expect(daemon).not_to receive(:launch)
              sleep(0.1) # Wait for process to do stuff.
              ::Process.kill('TERM', pid)
              should_exit_with(0) # It will exit with 1 if the expect fails.
            end
          end # with service1 running already
        end
      end # #execute

      describe '#handle_events', :handle_events do
        subject { static_services.handle_events }
        let(:mock_consul) { double('Podbay::Consul') }
        let(:mock_docker) { double('Podbay::Docker') }
        let(:mock_container_info) { double('Podbay::Docker::ContainerInfo') }

        around do |ex|
          Podbay::Consul.mock(mock_consul) do
            Podbay::Docker.mock(mock_docker) do
              Daemon::ContainerInfo.mock(mock_container_info) do
                ex.run
              end
            end
          end
        end

        let(:mock_service) { double('Podbay::Consul::Service') }
        let(:mock_lock) { double('Podbay::Consul::Lock') }
        let(:service_name) { 'service-name' }

        let(:service_action_resps) do
          [
            action_resp('restart', state: 'sync'),
            action_resp('restart', state: 'sync'),
            action_resp('restart', state: 'restart'),
            action_resp('restart', state: 'restart')
          ]
        end

        let(:action_id) { SecureRandom.uuid }
        let(:lock_ttl_remaining) { 9 }

        let(:service_ids) { ['service_id1', 'service_id2', 'service_id3'] }
        let(:resp_local_services) do
          service_ids.map { |id|
            [id, {'Service' => service_name, 'ID' => id }]
          }.to_h
        end
        let(:service_config) do
          {
            'image' => {
              'name' => 'test_name',
              'tag' => 'test_tag'
            }
          }
        end

        let(:container_images) { ["repo/#{service_name}:tag"] * 3 }
        let(:docker_containers) do
          container_images.map do |image|
            { 'Image' => image, 'id' => SecureRandom.hex(32) }
          end
        end


        let(:managed_services) { [service_name, service_name] }
        let(:daemon_launch_success) { true }
        let(:docker_pull_success) { true }
        let(:mock_logger) { double('mock logger', info: nil, warn: nil) }

        def action_resp(action, data = {})
          {
            id: action_id,
            name: action,
            data: data.symbolize_keys
          }
        end

        before do
          allow(mock_consul).to receive(:handle_events).with('action')
            .and_yield(event)

          allow(mock_consul).to receive(:service_healthy?).with(
            service_name, Socket.gethostname
            ).and_return(true)

          allow(mock_consul).to receive(:service).with(service_name)
            .and_return(mock_service)

          allow(mock_service).to receive(:action)
            .and_return(*service_action_resps)

          allow(mock_service).to receive(:lock).and_yield(mock_lock)
          allow(mock_service).to receive(:refresh_action)
          allow(mock_lock).to receive(:ttl_remaining)
            .and_return(lock_ttl_remaining)
          allow(mock_lock).to receive(:renew)

          allow(mock_service).to receive(:name).and_return(service_name.to_sym)

          allow(mock_consul).to receive(:local_services)
            .and_return(resp_local_services)
          allow(mock_consul).to receive(:deregister_local_service)

          allow(mock_docker).to receive(:containers)
            .and_return(docker_containers)

          allow(mock_container_info).to receive(:service_name)
            .and_return(service_name)

          allow(mock_docker).to receive(:stop)

          allow(static_services).to receive(:services)
            .and_return(managed_services)

          allow(daemon).to receive(:service_config).with(service_name)
            .and_return(service_config)

          allow(mock_docker).to receive(:pull).and_return(docker_pull_success)
          allow(daemon).to receive(:launch).with(service_name).and_return(
            daemon_launch_success
          )

          allow(daemon).to receive(:logger).and_return(mock_logger)
        end

        after { subject }

        def gen_action_event(service_name, action_id, channel = 'service')
          {
            'ID' => SecureRandom.uuid,
            'Name' => 'action',
            'Payload' => Base64
              .strict_encode64("#{channel}:#{service_name}:#{action_id}")
          }
        end

        let(:event) { gen_action_event(service_name, action_id) }

        it 'should lock the service with a 30s ttl' do
          expect(mock_service).to receive(:lock).with(ttl: 30).once
        end

        it 'should add itself to the synced_nodes' do
          expect(mock_service).to receive(:refresh_action).with(
            action_id, data: {
              state: 'sync',
              synced_nodes: [Socket.gethostname]
            }
          ).once
        end

        it 'should set the state to restarting' do
          expect(mock_service).to receive(:refresh_action)
            .with(action_id, data: hash_including(state: 'restarting'))
            .once
        end

        it 'should deregister services' do
          service_ids.each do |id|
            expect(mock_consul).to receive(:deregister_local_service)
              .with(id).once
          end
        end

        it 'should stop containers' do
          docker_containers.each do |v|
            expect(mock_docker).to receive(:stop).with(v['id']).once
          end
        end

        it 'should launch correct number of containers' do
          expect(daemon).to receive(:launch).with(service_name).exactly(
            managed_services.select { |s| s == service_name }.count
          ).times
        end

        it 'should add itself to the list of restarted_nodes' do
          expect(mock_service).to receive(:refresh_action).with(
            action_id, data: hash_including(
              state: 'restart',
              restarted_nodes: [Socket.gethostname]
            )
          ).once
        end

        context 'with non-service channel action' do
          let(:event) { gen_action_event(service_name, action_id, 'channel') }

          it 'should not handle the action' do
            expect(mock_consul).not_to receive(:service)
          end

          it 'should log that the action is being ignored' do
            expect(mock_logger).to receive(:info).with(
              "Ignoring action: #{Base64.strict_decode64(event['Payload']).inspect}"
            )
          end

          it { is_expected.to be nil }
        end

        context 'with restarting service not in managed services' do
          let(:managed_services) { ['another-service'] }

          it 'should not sync for restart' do
            expect(mock_service).not_to receive(:refresh_action).with(
              action_id, data: hash_including(
                synced_nodes: [Socket.gethostname]
              )
            )
          end
        end # with restarting service not in managed services

        context 'with daemon launch error' do
          let(:daemon_launch_success) { false }

          it 'should not add itself to the list of restarted_nodes' do
            expect(mock_service).not_to receive(:refresh_action).with(
              action_id, data: hash_including(
                state: 'restart',
                restarted_nodes: [Socket.gethostname]
              )
            )
          end

          it 'should abort the restart' do
            expect(mock_service).to receive(:refresh_action).with(
              action_id, data: hash_including(state: 'abort')
            )
          end
        end # with daemon launch error
      end # #handle_events
    end # StaticServices
  end # Daemon::Modules
end # Podbay::Components
