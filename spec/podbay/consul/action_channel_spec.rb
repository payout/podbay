class Podbay::Consul
  RSpec.describe ActionChannel do
    let(:action_channel) { ActionChannel.new(name) }
    let(:name) { 'action-name' }
    let(:consul_mock) { double('Podbay::Consul') }
    let(:kv_mock) { double('Podbay::Consul::Kv') }
    let(:lock_mock) { double('lock') }

    around do |ex|
      Podbay::Consul.mock(consul_mock) do
        Podbay::Consul::Kv.mock(kv_mock) do
          ex.run
        end
      end
    end

    describe '#new' do
      subject { ActionChannel.new(name) }

      it 'should set the name as an attribute' do
        expect(subject.name).to eq name.to_sym
      end
    end # #new

    describe '#lock', :lock do
      subject { action_channel.lock(opts, &lock_block) }

      before do
        # Simulate consul locking
        mutex = Mutex.new
        allow(consul_mock).to receive(:lock) do |&block|
          mutex.lock

          begin
            block.call(lock_mock)
          ensure
            mutex.unlock
          end
        end
      end

      after { subject }

      let(:lock_block) { proc { } }

      context 'with no options' do
        let(:opts) { {} }

        it 'should call Consul.lock with default ttl of 15' do
          expect(consul_mock).to receive(:lock)
            .with(instance_of(String), ttl: 15).once
        end

        it 'should call Consul.lock with correct lock name' do
          expect(consul_mock).to receive(:lock)
            .with("action:#{name}", instance_of(Hash)).once
        end

        it 'should yield lock to block' do
          expect { |b| action_channel.lock(opts, &b) }
            .to yield_with_args(lock_mock)
        end

        context 'with nested call' do
          let(:lock_block) { proc { action_channel.lock {} } }
          it { expect { subject }.not_to raise_error }
        end
      end # with no options

      context 'with ttl = 20' do
        let(:opts) { { ttl: 20 } }

        it 'should call Consul.lock with default ttl of 20' do
          expect(consul_mock).to receive(:lock)
            .with(instance_of(String), ttl: 20).once
        end
      end # with ttl = 20
    end # #lock

    describe '#begin_action', :begin_action do
      subject { action_channel.begin_action(action_name, opts) }
      let(:action_name) { 'action-name' }
      let(:opts) { {} }
      let(:resp_action?) { nil }
      let(:resp_defn) { {} }
      let(:current) { double('current action', expired?: current_expired?) }
      let(:current_expired?) { false }

      before do
        # Don't actually want to lock
        allow(action_channel).to receive(:lock).and_yield
        allow(action_channel).to receive(:in_use?).and_return(resp_action?)
        allow(action_channel).to receive(:current).and_return(current)
        allow(action_channel).to receive(:set_action) { |a| a.to_h }
        allow(kv_mock).to receive(:set)
        allow(consul_mock).to receive(:fire_event)
      end

      after { subject }

      context 'with no current action' do
        let(:resp_action?) { false }
        let(:current) { nil }

        context 'with no options' do
          let(:opts) { {} }

          it 'should return valid action definition' do
            is_expected.to have_attributes(
              id: a_string_matching(
                /\A[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}\z/),
              name: action_name,
              time: a_value_within(1).of(Time.now.to_i),
              ttl: 600
            )
          end

          it 'should fire expected event' do
            expect(consul_mock).to receive(:fire_event)
              .with(
                'action',
                /\A#{name}:[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}\z/
              ).once
          end
        end # with no options

        context 'with data = "my message"' do
          let(:opts) { { data: 'my message' } }
          it { is_expected.to have_attributes(data: opts[:data]) }
        end

        context 'with data as hash' do
          let(:opts) { { data: { key: 'value' } } }
          it { is_expected.to have_attributes(data: opts[:data]) }
        end

        context 'with ttl = 3600' do
          let(:opts) { { ttl: 3600 } }
          it { is_expected.to have_attributes(ttl: opts[:ttl]) }

          it 'should fire expected event' do
            expect(consul_mock).to receive(:fire_event)
              .with(
                'action',
                /\A#{name}:[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}\z/
              ).once
          end
        end
      end # with no current action

      context 'with current valid action' do
        let(:resp_action?) { true }
        let(:resp_defn) do
          {
            id: '1234-123',
            name: 'test-action',
            time: Time.now.to_i,
            ttl: 100
          }
        end
        it { is_expected.to be nil }
      end # with current valid action

      context 'with expired action' do
        let(:resp_action?) { true }
        let(:current_expired?) { true }
        it { is_expected.to be_a Action }
      end # with expired action
    end # #begin_action

    describe '#end_action', :end_action do
      subject { action_channel.end_action(action) }

      let(:action) { double('action', id: SecureRandom.uuid) }
      let(:current) { double('current', id: current_id) }
      let(:current_id) { action.id }

      before do
        # Don't actually want to lock
        allow(action_channel).to receive(:lock).and_yield
        allow(action_channel).to receive(:current).and_return(current)
        allow(kv_mock).to receive(:delete).and_return(true)
      end

      after { subject }

      context 'with correct action in progress' do
        let(:current_id) { action.id }

        it 'should delete action' do
          expect(kv_mock).to receive(:delete).with("actions/#{name}")
            .once
        end

        it { is_expected.to be true }
      end # with correct action in progress

      context 'with different action in progress' do
        let(:current_id) { SecureRandom.uuid }

        it 'should not clear action' do
          expect(kv_mock).not_to receive(:delete)
        end

        it { is_expected.to be false }
      end # with different action in progress
    end # #end_action

    describe '#in_use?' do
      subject { action_channel.in_use? }

      before do
        allow(action_channel).to receive(:current).and_return(action)
      end

      context 'with channel in use' do
        let(:action) { double('action') }
        it { is_expected.to be true }
      end # with channel in use

      context 'with not channel in use' do
        let(:action) { nil }
        it { is_expected.to be false }
      end # with not channel in use
    end # #in_use?

    describe '#current', :current do
      subject { action_channel.current }

      let(:kv_mock) { double('Podbay::Consul::Kv') }

      around do |ex|
        Podbay::Consul::Kv.mock(kv_mock) do
          ex.run
        end
      end

      before do
        allow(kv_mock).to receive(:get).and_return(defn)
      end

      let(:defn) { nil }

      context 'with current action' do
        let(:defn) do
          {
            id: '123-1234',
            name: 'action-name',
            time: Time.now.to_i,
            ttl: 300,
            data: { test: 'value' }
          }
        end

        it { is_expected.to be_a Action }
        it { is_expected.to have_attributes(defn) }
      end

      context 'with no current action' do
        it { is_expected.to be nil }
      end
    end # #current

    describe '#set_action' do
      subject { action_channel.set_action(action) }

      let(:action) { Action.new(action_channel, defn) }
      let(:defn) do
        {
          id: '123-1234',
          name: 'action-name',
          time: time,
          ttl: ttl,
          data: { test: 'value' }
        }
      end
      let(:time) { Time.now.to_i }
      let(:ttl) { 300 }
      let(:kv_mock) { double('Podbay::Consul::Kv') }

      around do |ex|
        Podbay::Consul::Kv.mock(kv_mock) do
          ex.run
        end
      end

      before do
        allow(action_channel).to receive(:lock).and_yield
        allow(action_channel).to receive(:current).and_return(action)
        allow(kv_mock).to receive(:set)
      end

      context 'with valid action' do
        let(:time) { Time.now.to_i }

        it { is_expected.to eq defn }

        it 'should set the action in the Kv store' do
          expect(kv_mock).to receive(:set).with('actions/action-name', defn)
          subject
        end

        context 'with older time' do
          let(:time) { Time.now.to_i - 10 }

          it 'should refresh the time' do
            expect(subject[:time]).to be > time
          end
        end
      end # with valid action

      context 'with expired action' do
        let(:time) { Time.now.to_i - ttl - 1 }

        it 'should raise an error' do
          expect { subject }.to raise_error Podbay::ActionExpiredError
        end

        context 'with new action taking place' do
          let(:new_action) do
            Action.new(action_channel, defn.merge(
              id: '567-5678',
              name: 'new-action',
              time: Time.now.to_i
            ))
          end

          before do
            allow(action_channel).to receive(:current).and_return(new_action)
          end

          it 'should raise an error' do
            expect { subject }.to raise_error Podbay::ActionExpiredError
          end
        end
      end # with expired action
    end # #set_action
  end # ActionChannel
end # Podbay::Consul
