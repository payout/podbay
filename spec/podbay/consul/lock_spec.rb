module Podbay
  class Consul
    describe Consul::Lock do
      let(:lock) { Consul::Lock.new(name, ttl) }
      let(:name) { 'my-lock' }
      let(:ttl) { 100 }
      let(:mock_consul) { double('Podbay::Consul') }

      around do |ex|
        Consul.mock(mock_consul) { ex.run }
      end

      describe '#new', :new do
        subject { lock }

        context 'with symbol lock name' do
          let(:name) { :mylock }

          it 'should convert name to string' do
            expect(subject.name).to eq name.to_s
          end
        end
      end # #new

      describe '#lock', :lock do
        subject { lock.lock }

        before do
          allow(mock_consul).to receive(:create_session).and_return(session_id)
          allow(mock_consul).to receive(:try_lock).and_return(*try_lock_resps)
          allow(mock_consul).to receive(:renew_session)
        end

        after { subject }

        let(:session_id) { SecureRandom.uuid }
        let(:try_lock_resps) { [true] }

        it 'should create a session with the appropriate name and ttl' do
          expect(mock_consul).to receive(:create_session)
            .with("for lock #{name}", ttl: ttl).once
        end

        it 'should try the appropriate lock' do
          expect(mock_consul).to receive(:try_lock).with(name, session_id).once
        end

        context 'with try_lock returning false at first' do
          let(:try_lock_resps) { [false, true] }

          context 'with ttl = 1000' do
            let(:ttl) { 1000 }

            it 'should sleep for maximum of 1s' do
              expect(lock).to receive(:sleep).with(1).once
            end
          end

          context 'with ttl = 15' do
            let(:ttl) { 15 }

            it 'should sleep for 0.15s' do
              expect(lock).to receive(:sleep).with(0.15).once
            end
          end

          context 'with ttl = 9' do
            let(:ttl) { 9 }

            it 'should sleep for 0.09s' do
              expect(lock).to receive(:sleep).with(0.09).once
            end
          end

          context 'with ttl = 0.1' do
            let(:ttl) { 0.1 }

            it 'should sleep for minimum of 0.01' do
              expect(lock).to receive(:sleep).with(0.01).once
            end
          end
        end # with try_lock returning false at first

        context 'with try_lock returning false until ttl has surpased 90%' do
          let(:ttl) { 15 }
          let(:try_lock_resps) { [false] * 91 + [true] }

          before do
            # 0.15 sleep time is required so that the 91 above will surpase
            # 90% of the ttl.
            allow(lock).to receive(:sleep).with(0.15)
          end

          it 'should renew the lock once before returning' do
            expect(lock).to receive(:renew).once
          end
        end # with try_lock returning false until ttl has surpased 90%

        context 'with try_lock returning false until ttl has surpased 5%' do
          let(:ttl) { 15 }
          let(:try_lock_resps) { [false] * 6 + [true] }

          before do
            # 0.15 sleep time is required so that the 6 above will surpase
            # 5% of the ttl.
            allow(lock).to receive(:sleep).with(0.15)
          end

          it 'should renew the lock once before returning' do
            expect(lock).to receive(:renew).once
          end
        end # with try_lock returning false until ttl has surpased 5%
      end # #lock
    end # Lock
  end # Consul
end # Podbay