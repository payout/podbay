module Podbay
  class Consul
    describe Kv do
      describe '::get', :get do
        subject { Consul::Kv.get(root, opts) }
        around { |ex| Consul::Kv.mock_store(mock_store) { ex.run } }
        before { allow(mock_store).to receive(:get).and_return(kv_response) }

        let(:root) { 'root/key' }
        let(:mock_store) { double('mock store') }
        let(:kv_response) { nil }
        let(:opts) { {} }

        context 'with json hash' do
          let(:kv_response) { '{"hello":"there"}' }
          it { is_expected.to eq(hello: 'there') }
        end

        context 'with json array' do
          let(:kv_response) { '[1,2,3]' }
          it { is_expected.to eq [1,2,3] }
        end

        context 'with string' do
          let(:kv_response) { 'this is a string' }
          it { is_expected.to eq 'this is a string' }
        end

        context 'with key not found' do
          before do
            allow(mock_store).to receive(:get) { fail Diplomat::KeyNotFound }
          end

          it { is_expected.to be nil }
        end # with key not found

        context 'with options' do
          let(:opts) { { test: 'test' } }
          let(:kv_response) { 'test' }

          it 'should pass in the options' do
            expect(mock_store).to receive(:get).with(root, opts)
            subject
          end
        end # with options
      end # ::get

      describe '::set', :set do
        subject { Consul::Kv.set(root_key, object) }
        let(:root_key) { 'root/key' }
        let(:mock_store) { double('mock store') }
        let(:mock_consul) { double('Consul') }

        around do |ex|
          Consul::Kv.mock_store(mock_store) do
            Consul.mock(mock_consul) do
              ex.run
            end
          end
        end

        before do
          allow(mock_store).to receive(:put)
        end

        after { subject }

        context 'with string object' do
          let(:object) { 'this is a string' }

          it 'should use string as value for key' do
            expect(mock_store).to receive(:put).with(root_key, object)
          end
        end

        context 'with hash object' do
          let(:object) { {key: 'value', 'key2' => 'value2'} }

          it 'should JSONify the hash before putting it as the value' do
            expect(mock_store).to receive(:put)
              .with(root_key, JSON.dump(object))
          end
        end

        context 'with array object' do
          let(:object) { [1,2,3] }

          it 'should JSONify the array before putting it as the value' do
            expect(mock_store).to receive(:put)
              .with(root_key, JSON.dump(object))
          end
        end
      end # ::set
    end
  end
end