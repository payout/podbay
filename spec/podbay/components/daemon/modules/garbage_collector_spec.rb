module Podbay::Components
  class Daemon::Modules
    RSpec.describe GarbageCollector do
      let(:daemon) { Daemon.new }
      let(:garbage_collector) { GarbageCollector.new(daemon) }

      def expect_system(command)
        expect(garbage_collector).to receive(:system).with(command).once
      end

      describe '#execute', :execute do
        subject { process }
        let(:process) { garbage_collector.execute(period: 1) }

        before do
          allow(garbage_collector).to receive(:collect)
          allow(garbage_collector).to receive(:sleep)
        end

        after { process.kill }

        def should_exit_with(code)
          _, status = ::Process.wait2(process.pid)
          expect(status.exitstatus).to eq code
        end

        it 'should call #collect' do
          allow(garbage_collector).to receive(:collect) { exit 5 }
          should_exit_with(5)
        end

        it 'should call #collect multiple times' do
          count = 0
          allow(garbage_collector).to receive(:collect) do
            exit 6 if (count += 1) > 2
          end

          should_exit_with(6)
        end

        it 'should sleep for 1 second' do
          allow(garbage_collector).to receive(:sleep).with(1) { exit 7 }
          should_exit_with(7)
        end

        it 'should call #sleep multiple times' do
          count = 0
          allow(garbage_collector).to receive(:sleep).with(1) do
            exit 8 if (count += 1) > 2
          end

          should_exit_with(8)
        end
      end

      describe '#collect', :collect do
        subject { garbage_collector.collect }

        let(:mock_docker) { double('Podbay::Docker') }
        let(:mock_loop_devices) { double('Daemon::LoopDevices') }
        let(:mock_container_info) { double('Daemon::ContainerInfo') }

        let(:containers) { [{'id' => 'abcdefghijkl'}] }
        let(:container_binds) {
          ['/dev/log:/dev/log','/var/podbay/loop/mounts/1234abcd:/tmp']
        }

        let(:mount_paths_listing) {
          [
            '/var/podbay/loop/mounts/5678abcd',
            '/var/podbay/loop/mounts/1234abcd'
          ]
        }

        let(:container_info_list) { [] }

        around do |ex|
          Podbay::Docker.mock(mock_docker) do
            Daemon::LoopDevices.mock(mock_loop_devices) do
              Daemon::ContainerInfo.mock(mock_container_info) do
                ex.run
              end
            end
          end
        end

        before do
          allow(daemon.logger).to receive(:info)
          allow(garbage_collector).to receive(:system)

          allow(mock_docker).to receive(:containers)
            .and_return(containers)
          allow(mock_docker).to receive(:container_binds)
            .and_return(container_binds)

          allow(mock_loop_devices).to receive(:mounts_path)
            .and_return('/var/podbay/loop/mounts')
          allow(mock_loop_devices).to receive(:mount_paths_listing)
            .and_return(mount_paths_listing)

          allow(mock_loop_devices).to receive(:remove)

          allow(mock_container_info).to receive(:list)
            .and_return(container_info_list)

          allow(mock_container_info).to receive(:cleanup)
        end

        after { subject }

        it 'should log start' do
          expect(daemon.logger).to receive(:info)
            .with('Garbage collection started...').once
        end

        it 'should log completion' do
          expect(daemon.logger).to receive(:info)
            .with('Garbage collection completed.').once
        end

        it 'should call docker daemon cleanup commands' do
          expect_system('docker ps -a -q | xargs --no-run-if-empty docker rm ' \
            '> /dev/null 2>&1')
          expect_system('docker images -q | xargs --no-run-if-empty docker ' \
            'rmi > /dev/null 2>&1')
        end

        context 'with an unused loop mount directory' do
          let(:container_binds) {
            ['/dev/log:/dev/log','/var/podbay/loop/mounts/1234abcd:/tmp']
          }

          it 'should remove an unused loop mount' do
            expect(mock_loop_devices).to receive(:remove)
              .with(mount_paths_listing[0])
          end

          it 'should not remove a used loop mount' do
            expect(mock_loop_devices).not_to receive(:remove)
              .with(mount_paths_listing[1])
          end
        end

        context 'with only used loop mount directories' do
          let(:mount_paths_listing) { ['/var/podbay/loop/mounts/1234abcd'] }
          let(:container_binds) {
            ['/dev/log:/dev/log','/var/podbay/loop/mounts/1234abcd:/tmp']
          }

          it 'should remove no loop mounts' do
            expect(mock_loop_devices).not_to receive(:remove)
          end
        end

        context 'with container info list containing running containers' do
          let(:container_info_list) { containers.map { |c| c['id'] } }

          it 'should not cleanup container info' do
            expect(mock_container_info).not_to receive(:cleanup)
            subject
          end
        end

        context 'with container info having old containers' do
          let(:running_containers) { containers.map { |c| c['id'] } }
          let(:old_containers) { ['old-container1', 'old-container2'] }
          let(:container_info_list) { old_containers + running_containers }

          it 'should cleanup old containers' do
            old_containers.each do |id|
              expect(mock_container_info).to receive(:cleanup).with(id).once
            end

            subject
          end

          it 'should not cleanup running containers' do
            running_containers.each do |id|
              expect(mock_container_info).not_to receive(:cleanup).with(id)
            end

            subject
          end
        end
      end # #execute
    end # GarbageCollector
  end # Daemon::Modules
end # Podbay::Components
