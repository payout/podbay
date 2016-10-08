class Podbay::Consul
  RSpec.describe Action do
    let(:action) { Action.new(channel, defn) }
    let(:channel) { double('ActionChannel') }
    let(:defn) { {} }

    describe '#new', :new do
      subject { Action.new(channel, defn) }
      let(:defn) do
        {
          id: '1234-12345-1234',
          name: 'action-name',
          time: Time.now.to_i,
          ttl: 300,
          data: { example_key: 'example_field' }
        }
      end

      it 'should set the channel' do
        expect(subject.channel).to eq channel
      end

      it 'should set all of the action attributes' do
        expect(subject).to have_attributes(
          defn
        )
      end
    end # #new

    describe '#refresh', :refresh do
      subject { action.refresh }

      before do
        allow(channel).to receive(:current).and_return(current)
        allow(action).to receive(:expired?).and_return(is_expired)
      end

      let(:current) { double('current', id: id, time: time, data: data) }
      let(:id) { action.id }
      let(:time) { Time.now.to_i }
      let(:is_expired) { false }
      let(:data) { { test: 'test' } }

      context 'with different action ids' do
        let(:id) { '1234-12345' }
        it 'should raise an error' do
          expect { subject }.to raise_error Podbay::ActionExpiredError
        end
      end

      context 'with action expired' do
        let(:is_expired) { true }

        it 'should raise an error' do
          expect { subject }.to raise_error Podbay::ActionExpiredError
        end
      end

      context 'with valid action' do
        it 'should update its data' do
          expect(action.data).to eq({})
          subject
          expect(action.data).to eq(data)
        end

        context 'with older time' do
          let(:defn) do
            {
              time: old_time
            }
          end
          let(:old_time) { Time.now.to_i - 5 }

          it 'should update its time' do
            expect(action.time).to eq(old_time)
            subject
            expect(action.time).to eq(time)
          end
        end # with older time
      end
    end # #refresh

    describe '#lock', :lock do
      subject { action.lock({ttl: ttl}, &block) }

      let(:block) { proc { } }
      let(:ttl) { 20 }
      let(:lock) { double('lock') }

      before do
        allow(channel).to receive(:lock).and_yield(lock)
        allow(action).to receive(:refresh)
      end

      it 'should call lock on channel' do
        expect(channel).to receive(:lock).with({ttl: ttl}, &block)
          .and_yield(lock)
        subject
      end

      it 'should refresh the action' do
        expect(action).to receive(:refresh)
        subject
      end
    end # #lock

    describe '#[]' do
      subject { action[key] }

      context 'with key existing' do
        let(:defn) do
          {
            data: { key: 'value' }
          }
        end
        let(:key) { :key }

        it { is_expected.to eq 'value' }
      end

      context 'with key not existing' do
        let(:key) { :nonexistent_key }
        it { is_expected.to be nil }
      end
    end # #[]

    describe '#[]=' do
      subject { action[key] = value }

      let(:key) { :some_key }
      let(:value) { :some_value }

      it 'should set the value in data' do
        subject
        expect(action.data).to eq(key => value)
      end
    end # #[]=

    describe '#save', :save do
      subject { action.save }

      before do
        allow(channel).to receive(:set_action).and_return(updated_defn)
      end

      let(:updated_defn) do
        defn.merge(time: updated_time)
      end
      let(:updated_time) { Time.now.to_i }
      let(:defn) do
        {
          id: '1234-12345-1234',
          name: 'action-name',
          time: Time.now.to_i - 5,
          ttl: 300,
          data: { example_key: 'example_field' }
        }
      end

      it 'should call set_action on channel' do
        expect(channel).to receive(:set_action).with(action)
        subject
      end

      it 'should update its time' do
        subject
        expect(action.time).to eq updated_time
      end
    end # #save

    describe '#end', :end do
      subject { action.end }

      it 'should call end_action on channel' do
        expect(channel).to receive(:end_action).with(action)
        subject
      end
    end # #end

    describe '#expired?' do
      subject { action.expired? }

      let(:defn) do
        {
          id: '1234-12345-1234',
          name: 'action-name',
          time: time,
          ttl: ttl,
          data: { example_key: 'example_field' }
        }
      end
      let(:time) { Time.now.to_i }
      let(:ttl) { 300 }

      context 'with action expired' do
        let(:time) { Time.now.to_i - ttl - 1 }
        it { is_expected.to be true }
      end

      context 'with action not expired' do
        let(:time) { Time.now.to_i }
        let(:ttl) { 300 }

        it { is_expected.to be false }
      end
    end # #expired?

    describe '#to_h' do
      subject { action.to_h }

      let(:defn) do
        {
          id: '1234-12345-1234',
          name: 'action-name',
          time: Time.now.to_i,
          ttl: 300,
          data: { example_key: 'example_field' }
        }
      end

      it { is_expected.to include(defn) }
    end # #to_h
  end # Action
end # Podbay::Consul
