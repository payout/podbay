require 'tmpdir'

class Podbay::Components::Daemon
  RSpec.describe ContainerInfo do
    let(:container_info) { ContainerInfo.new }

    describe '#write_service_name', :write_service_name do
      subject do
        container_info.write_service_name(container_id, service_name, path: path)
      end

      let(:container_id) { SecureRandom.hex(32) }
      let(:service_name) { 'my_service_name' }
      let(:path) { Dir.mktmpdir }
      let(:file_path) { "#{path}/#{container_id}" }

      it 'should create container file' do
        expect(File.exists?(file_path)).not_to be true
        subject
        expect(File.exists?(file_path)).to be true
      end

      it 'should write service name to file' do
        subject
        expect(File.read(file_path)).to eq service_name
      end
    end # #write_service_name

    describe '#service_name', :service_name do
      subject do
        container_info.service_name(container_id, wait: wait, path: path)
      end

      let(:container_id) { SecureRandom.hex(32) }
      let(:service_name) { 'my_service_name' }
      let(:path) { Dir.mktmpdir }
      let(:wait) { 0.1 }
      let(:file_path) { "#{path}/#{container_id}" }

      after { `rm -r #{path}` }

      context 'with container file existing' do
        before { File.write(file_path, service_name) }
        it { is_expected.to eq service_name }
      end

      context 'with container file missing' do
        it { is_expected.to be nil }

        it 'should sleep 5 times' do
          expect(container_info).to receive(:sleep).with(0.1 / 5).exactly(5)
            .times
          subject
        end
      end
    end # #service_name

    describe '#list', :list do
      subject { container_info.list(path: path) }
      let(:path) { Dir.mktmpdir }
      after { `rm -r #{path}` }

      context 'with empty path' do
        it { is_expected.to eq [] }
      end

      context 'with 3 files in path' do
        let(:files) { 3.times.map { SecureRandom.hex(32) } }
        before { files.each { |f| `touch #{path}/#{f}` } }
        it { is_expected.to match_array(files) }
      end
    end # #list

    describe '#cleanup', :cleanup do
      subject { container_info.cleanup(container_id, path: path) }
      let(:path) { Dir.mktmpdir }
      let(:container_id) { SecureRandom.hex(32) }
      let(:file_path) { "#{path}/#{container_id}" }

      before { `touch #{file_path}` }
      after { `rm -r #{path}` }

      it 'should remove file' do
        expect(File.exists?(file_path)).to be true
        subject
        expect(File.exists?(file_path)).to be false
      end
    end # #cleanup
  end # ContainerInfo
end # Podaby::Components::Daemon
