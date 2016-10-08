module Podbay
  module Components
    RSpec.describe Base do
      let(:base) { Base.new(options) }

      describe '#options' do
        let(:options) { { cluster: 'value' } }
        subject { base.options }
        it { is_expected.to eq options }
        it { is_expected.not_to be options }
        it { is_expected.to be_frozen }
      end # #options

      describe '#service' do
        subject { base.service }

        let(:options) { { service: 'test-service' } }

        it { is_expected.to eq 'test-service' }

        context 'with no service option' do
          let(:options) { {} }

          it 'should raise an error' do
            expect { subject }.to raise_error '--service must be specified'
          end
        end
      end # #service

      describe '#cluster' do
        subject { base.cluster }

        let(:options) { { cluster: 'test-cluster' } }

        it { is_expected.to eq 'test-cluster' }

        context 'with no cluster option' do
          let(:options) { {} }

          it 'should raise an error' do
            expect { subject }.to raise_error '--cluster must be specified'
          end
        end
      end # #cluster
    end # Base
  end # Components
end # Podbay