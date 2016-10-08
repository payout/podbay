module Podbay
  class Components::Daemon::Modules
    class Consul
      RSpec.describe Backups do
        let(:backups) { Backups.new }

        describe '#load' do
          subject { backups.load(URI(uri)) }

          let(:s3_file_mock) { double('S3File') }

          around do |ex|
            Podbay::Utils::S3File.mock(s3_file_mock) do
              ex.run
            end
          end

          context 'with uri=s3://path-to-backup' do
            before do
              allow(s3_file_mock).to receive(:new).and_return(double(read: nil))
            end

            let(:uri) { 's3://path-to-backup' }

            it { is_expected.to be_a Backups::S3Backup }

            it 'should create the s3 instance' do
              expect(subject.bucket).to eq 'path-to-backup'
            end
          end

          context 'with nonexistent-store' do
            let(:uri) { 'nonexistent-store://path-to-backup' }
            it { is_expected.to be nil }
          end
        end # #load
      end # Backups
    end # Consul
  end # Components::Daemon::Modules
end # Podbay
