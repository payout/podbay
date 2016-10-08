class Podbay::Consul
  RSpec.describe Service do
    let(:service) { Service.new(service_name) }
    let(:service_name) { 'service-name' }

    describe '#new' do
      subject { Service.new(service_name) }

      it 'should set the service_name' do
        expect(subject.name).to eq service_name.to_sym
      end
    end # #new

    describe '#lock' do
      subject { service.lock({ttl: ttl}, &block) }

      let(:block) { proc { } }
      let(:ttl) { 30 }

      before do
        allow(service).to receive(:action_channel).and_return(action_channel)
      end

      let(:action_channel) { double('action channel') }

      it 'should call lock on action_channel' do
        expect(action_channel).to receive(:lock).with({ttl: ttl}, &block)
        subject
      end
    end # #lock

    describe '#begin_action' do
      subject { service.begin_action(action_name, opts) }

      let(:action_name) { 'action-name' }
      let(:opts) do
        {
          ttl: 300,
          data: { hello: 'world' }
        }
      end

      before do
        allow(service).to receive(:action_channel).and_return(action_channel)
      end

      let(:action_channel) { double('action channel') }

      it 'should call begin_action on action_channel' do
        expect(action_channel).to receive(:begin_action)
          .with(action_name, opts)
        subject
      end
    end # #begin_action

    describe '#refresh_action' do
      subject { service.refresh_action(action_id, data) }

      let(:action_id) { '1234-123' }
      let(:data) { { data: {} } }
      let(:id) { action_id }
      let(:action) { double('action', id: id, data: nil, save: nil) }
      let(:opts) do
        {
          ttl: 300,
          data: { hello: 'world' }
        }
      end
      let(:action_channel) { double('action channel') }

      before do
        allow(service).to receive(:action_channel).and_return(action_channel)
        allow(action_channel).to receive(:current).and_return(action)

        allow(action).to receive(:data=)
        allow(action).to receive(:save)
      end

      context 'with valid action' do
        let(:data) do
          {
            data: { hello: :world }
          }
        end

        it { is_expected.to be true }

        it 'should set the data' do
          expect(action).to receive(:data=).with(data[:data])
          subject
        end

        it 'should save the action' do
          expect(action).to receive(:save)
          subject
        end
      end

      context 'with another action in progress' do
        let(:id) { '234-2345' }
        it { is_expected.to be false }
      end

      context 'with action.save raising exception' do
        before do
          allow(action).to receive(:save).and_raise(Podbay::ActionExpiredError)
        end

        it { is_expected.to be false }
      end
    end # #refresh_action

    describe '#end_action' do
      subject { service.end_action(action_id) }

      let(:action_id) { '1234-123' }
      let(:id) { action_id }
      let(:action) { double('action', id: id, data: nil, save: nil) }
      let(:opts) do
        {
          ttl: 300,
          data: { hello: 'world' }
        }
      end
      let(:action_channel) { double('action channel') }

      before do
        allow(service).to receive(:action_channel).and_return(action_channel)
        allow(action_channel).to receive(:current).and_return(action)
        allow(action).to receive(:end).and_return(true)
      end

      context 'with valid action' do
        it { is_expected.to be true }

        it 'should end the action' do
          expect(action).to receive(:end)
          subject
        end
      end

      context 'with another action in progress' do
        let(:id) { '234-2345' }
        it { is_expected.to be false }
      end
    end # #end_action

    describe '#action?' do
      subject { service.action? }

      before do
        allow(service).to receive(:action_channel).and_return(action_channel)
      end

      let(:action_channel) { double('action channel', in_use?: in_use) }
      let(:in_use) { true }

      context 'with channel in use' do
        let(:in_use) { true }
        it { is_expected.to be true  }
      end

      context 'with channel not in use' do
        let(:in_use) { false }
        it { is_expected.to be false  }
      end
    end # #action?

    describe '#action' do
      subject { service.action }

      before do
        allow(service).to receive(:action_channel).and_return(action_channel)
      end

      let(:action_channel) { double('action channel', current: current) }
      let(:defn) { { id: '1234-123' } }
      let(:current) { double('action', to_h: defn) }

      it { is_expected.to eq defn }
    end # #action

    describe '#action_channel' do
      subject { service.action_channel }
      it { is_expected.to be_a ActionChannel }
    end # #action_channel
  end # Service
end # Podbay::Consul
