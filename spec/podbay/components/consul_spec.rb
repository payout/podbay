module Podbay
  module Components
    RSpec.describe Consul do
      let(:consul) { Consul.new }

      describe '#gossip_rotate_key', :gossip_rotate_key do
        subject { consul.gossip_rotate_key }

        let(:mock_consul) { double('Podbay::Consul') }

        around { |ex| Podbay::Consul.mock(mock_consul) { ex.run } }

        before do
          allow(mock_consul).to receive(:lock).and_yield(lock_obj)
          allow(mock_consul).to receive(:fire_event)
          allow(mock_consul).to receive(:wait_for_flag)
            .and_return(true)
          allow(lock_obj).to receive(:renew)
        end

        let(:lock_obj) { double('Podbay::Consul::Lock') }

        after { subject }

        it 'should lock gossip_rotate_key' do
          expect(mock_consul).to receive(:lock)
            .with(:gossip_rotate_key, ttl: 600).once
        end

        it 'should fire proper event' do
          expect(mock_consul).to receive(:fire_event)
            .with(Podbay::Consul::GOSSIP_KEY_ROTATION_EVENT_NAME).once
        end

        context 'with wait_for_flag :gossip_rotate_key_begin returning false' do
          before do
            allow(mock_consul).to receive(:wait_for_flag)
              .with(:gossip_rotate_key_begin, ttl: 60).and_return(false)
          end

          it 'should not wait for end' do
            expect(mock_consul).not_to receive(:wait_for_flag)
              .with(:gossip_rotate_key_end, instance_of(Hash))
          end
        end # with wait_for_flag :gossip_rotate_key_begin returning false

        context 'with wait_for_flag :gossip_rotate_key_begin returning true' do
          before do
            allow(mock_consul).to receive(:wait_for_flag)
              .with(:gossip_rotate_key_begin, ttl: 60).and_return(true)
          end

          it 'should renew lock' do
            expect(lock_obj).to receive(:renew).once
          end

          it 'should wait for end' do
            expect(mock_consul).to receive(:wait_for_flag)
              .with(:gossip_rotate_key_end, ttl: 599)
          end

          context 'without successful end' do
            before do
              expect(mock_consul).to receive(:wait_for_flag)
                .with(:gossip_rotate_key_end, ttl: 599).and_return(false)
            end

            it { expect { subject }.not_to raise_error }
          end # without successful end

          context 'with successful end' do
            before do
              expect(mock_consul).to receive(:wait_for_flag)
              .with(:gossip_rotate_key_end, ttl: 599).and_return(true)
            end

            it { expect { subject }.not_to raise_error }
          end # with successful end
        end # with wait_for_flag :gossip_rotate_key_begin returning true
      end # #gossip_rotate_key

      describe '#kv_restore' do
        subject { consul.kv_restore(time) }

        let(:consul_mock) { double('Podbay::Consul') }

        around do |ex|
          Podbay::Consul.mock(consul_mock) do
            ex.run
          end
        end

        before do
          allow(consul).to receive(:loop).and_yield
          allow(consul).to receive(:sleep)
          allow(consul_mock).to receive(:begin_action).and_return(action)

          if action
            allow(action).to receive(:[]).with(:state).and_return(action_state)
            allow(action).to receive(:[]).with(:time_restored_to)
              .and_return(time_restored_to)
          end
        end

        after { subject rescue nil }

        let(:time) { Time.now.to_s }
        let(:action) { double('action', refresh: nil, end: nil) }
        let(:action_state) { 'restoring' }
        let(:time_restored_to) { 1.hour.ago.to_s }

        it 'should begin the action' do
          allow(consul_mock).to receive(:begin_action).with(
            Podbay::Consul::RESTORE_KV_EVENT_NAME,
            ttl: 60,
            data: { state: 'restoring', time: time }
          )
        end

        it 'should refresh the action' do
          expect(action).to receive(:refresh)
        end

        context 'with action already in progress' do
          let(:action) { nil }

          it 'should raise an error' do
            expect { subject }.to raise_error('another action is in progress')
          end
        end

        context 'with action = restored' do
          let(:action_state) { 'restored' }

          it 'should log the correct message' do
            expect(consul).to receive(:puts)
              .with("KVs successfully restored to #{time_restored_to}".green)
          end

          it 'should end the action' do
            expect(action).to receive(:end)
          end
        end

        context 'with action = failed' do
          let(:action_state) { 'failed' }

          it 'should log the correct message' do
            expect(consul).to receive(:puts).with('Restoration failed'.red)
          end

          it 'should end the action' do
            expect(action).to receive(:end)
          end
        end
      end # #kv_restore
    end # Consul
  end # Components
end # Podbay
