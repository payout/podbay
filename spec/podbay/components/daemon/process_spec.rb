require 'etc'

class Podbay::Components::Daemon
  RSpec.describe Process do
    let(:process) { Process.new }
    let(:pid) { subject.pid }
    let(:options) { nil }

    describe '#spawn', :spawn do
      subject { process.spawn(command, options, &block) }
      after { process.reap }

      context 'with command = sleep 10 and block nil' do
        let(:command) { 'sleep 10' }
        let(:block) { nil }
        it { is_expected.to eq process }

        it 'should set #pid' do
          is_expected.to have_attributes(pid: Integer)
        end

        it 'should create a process group for the spawned process' do
          expect(pid).to eq ::Process.getpgid(pid)
        end
      end # with command = sleep and block nil

      context 'with command = sleep 10 and block not nil' do
        let(:command) { 'sleep 10' }
        let(:block) { proc { sleep 10 } }

        it 'should raise error' do
          expect { subject }.to raise_error 'cannot specify both command and ' \
            'block'
        end
      end # with command = sleep and block not nil

      context 'with command nil and block nil' do
        let(:command) { nil }
        let(:block) { nil }

        it 'should raise error' do
          expect { subject }.to raise_error 'must specify either command or ' \
            'block'
        end
      end # with command nil and block nil

      context 'with command nil and block exiting with 10' do
        let(:command) { nil }
        let(:block) { proc { sleep 0.1; exit 10 } }

        it { is_expected.to eq process }

        it 'should set #pid' do
          is_expected.to have_attributes(pid: Integer)
        end

        it 'should create a process group for the spawned process' do
          expect(pid).to eq ::Process.getpgid(pid)
        end

        it 'should exit with 10' do
          expect(::Process.wait2(pid).last.exitstatus).to eq 10
        end
      end # with command nil and block exiting with 10

      context 'with name and group options specified' do
        # Note this test only tests that the logic doesn't cause errors.
        # We're not actually dropping privileges here since our test
        # environments won't always have the same users available.
        let(:username) { Etc.getlogin }
        let(:group_name) { Etc.getgrgid.name }
        let(:command) { nil }
        let(:options) { { user: username, group: group_name } }

        let(:block) do
          proc do
            unless Etc.getlogin == username && Etc.getgrgid.name == group_name
              exit 1
            end
          end
        end

        it 'should exit with 0' do
          # It will exit 1 if the username and group don't match what's
          # expected.
          expect(::Process.wait2(pid).last.exitstatus).to eq 0
        end
      end # with name and group options specified
    end # #spawn

    describe '#respawn', :respawn do
      subject { process.respawn }
      after { process.reap }
      let(:pid) { subject.pid }

      context 'before being spawned' do
        it { is_expected.to be nil }
      end # before being spawned

      context 'after being spawned' do
        let(:orig_pid) { process.spawn(command) }
        before { orig_pid }

        context 'with command = sleep 10' do
          let(:command) { 'sleep 10' }

          it { is_expected.to eq process }
          it { expect(pid).not_to eq orig_pid }

          it 'should should updated #pid' do
            is_expected.to have_attributes(pid: pid)
          end

          it 'should create a process group for the respawned process' do
            expect(pid).to eq ::Process.getpgid(pid)
          end
        end # with command = sleep 10
      end # after being spawned
    end # #respawn

    describe '#reap', :reap do
      subject { process.reap }

      context 'before being spawned' do
        it { is_expected.to be nil }
      end # before being spawned

      context 'after being spawned' do
        let(:pid) { process.spawn(command).pid }
        before { pid }

        context 'with command = sleep 10' do
          let(:command) { 'sleep 10' }
          it { is_expected.to be nil }

          it 'should not leave any processes behind' do
            subject
            expect { ::Process.wait(-pid, ::Process::WNOHANG) }
              .to raise_error Errno::ECHILD, 'No child processes'
          end
        end # with command = sleep 10
      end # after being spawned
    end # #reap

    describe '#term', :term do
      subject { process.term }
      let(:pid) { process.spawn(command).pid }

      context 'before being spawned' do
        it { is_expected.to be nil }
      end

      context 'after being spawned' do
        before { pid; subject; sleep 0.01 }
        after { process.reap } # Clean up

        context 'with command = sleep 10' do
          let(:command) { 'sleep 10' }

          it 'should cause the process to exit' do
            expect(::Process.wait(pid, ::Process::WNOHANG)).to eq pid
          end
        end # with command = sleep 10
      end # after being spawned
    end # #term

    describe '#kill', :kill do
      subject { process.kill }
      let(:pid) { process.spawn(command).pid }

      context 'before being spawned' do
        it { is_expected.to be nil }
      end

      context 'after being spawned' do
        before { pid; subject; sleep 0.01 }
        after { process.reap } # Clean up

        context 'with command = sleep 10' do
          let(:command) { 'sleep 10' }

          it 'should cause the process to exit' do
            expect(::Process.wait(pid, ::Process::WNOHANG)).to eq pid
          end
        end # with command = sleep 10
      end # after being spawned
    end # #kill
  end # Process
end # Podbay::Components::Daemon
