module Podbay
  class Components::Aws
    RSpec.describe AwsUtils do
      describe '::default_database_port' do
        subject { AwsUtils.default_database_port(engine) }

        context 'with engine=postgres' do
          let(:engine) { 'postgres' }
          it { is_expected.to eq 5432 }
        end

        context 'with engine=mariadb' do
          let(:engine) { 'mariadb' }
          it { is_expected.to eq 3306 }
        end

        context 'with invalid engine' do
          let(:engine) { 'invalid_engine' }

          it 'should raise an error' do
            expect { subject }.to raise_error 'no default port for engine ' \
              'invalid_engine'
          end
        end
      end # ::default_database_port

      describe '::default_cache_port' do
        subject { AwsUtils.default_cache_port(engine) }

        context 'with engine=redis' do
          let(:engine) { 'redis' }
          it { is_expected.to eq 6379 }
        end

        context 'with engine=memcached' do
          let(:engine) { 'memcached' }
          it { is_expected.to eq 11211 }
        end

        context 'with invaild engine' do
          let(:engine) { 'invalid_engine' }

          it 'should raise an error' do
            expect { subject }.to raise_error 'no default port for engine ' \
              'invalid_engine'
          end
        end
      end # ::default_cache_port

      describe '::cleanup_resources' do
        subject { AwsUtils.cleanup_resources(*resources) }

        let(:resources) { [] }
        let(:resource) { double('resource', delete: true) }

        after { subject }

        context 'with a single resource' do
          let(:resources) { [resource] }

          it 'should delete the resource' do
            expect(resource).to receive(:delete).once
          end
        end

        context 'with multiple resources' do
          let(:resources) { [resource, resource] }

          it 'should delete the resources' do
            expect(resource).to receive(:delete).twice
          end
        end

        context 'with nil resource passed in' do
          let(:resources) { [resource, nil] }

          it 'should delete the resources' do
            expect(resource).to receive(:delete).once
          end
        end

        context 'with array of resources passed in' do
          let(:resources) { [[resource, resource], resource] }

          it 'should delete the resources' do
            expect(resource).to receive(:delete).exactly(3).times
          end
        end
      end # ::cleanup_resources
    end # AwsUtils
  end # Components::Aws
end # Podbay