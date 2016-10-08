module Podbay
  module Components
    module Aws::Resources
      class AutoScaling
        RSpec.describe Waiter do
          let(:waiter) { Waiter.new }

          describe '#wait_until_group_has_size' do
            subject do
              waiter.wait_until_group_has_size(group, size, timeout, delay)
            end

            let(:asg_mock) { double('Resources::AutoScaling') }
            let(:group) { double('group', name: 'group') }
            let(:timeout) { 2 }
            let(:delay) { 1 }
            let(:size) { 0 }

            before do
              allow(asg_mock).to receive(:group).and_return(group)
              allow(group).to receive(:instances)
                .and_return(
                  (size + 1).times.map { double('instance')},
                  size.times.map { double('instance') }
                )
            end

            around { |ex| AutoScaling.mock(asg_mock) { ex.run } }

            it { is_expected.to be_nil }

            context 'with size=3' do
              let(:size) { 3 }
              it { is_expected.to be_nil }
            end

            context 'with autoscaling group not empty' do
              let(:delay) { 2 }

              it 'should raise an error' do
                expect { subject }.to raise_error ResourceWaiterError,
                  'AutoScaling Group did not reach desired size of 0'
              end
            end
          end # #wait_until_group_has_size

          describe '#wait_until_no_scaling_activities' do
            subject do
              waiter.wait_until_no_scaling_activities(group, timeout, delay)
            end

            let(:asg_mock) { double('Resources::AutoScaling') }
            let(:group) { double('group', name: 'group') }
            let(:timeout) { 2 }
            let(:delay) { 1 }

            before do
              allow(asg_mock).to receive(:group).and_return(group)
              allow(group).to receive(:activities).and_return(activities)
            end

            around { |ex| AutoScaling.mock(asg_mock) { ex.run } }

            let(:activities) { [double('activity', end_time: Time.now.to_s)] }

            it { is_expected.to be_nil }

            context 'with scaling activities not ending' do
              let(:activities) { [double('activity', end_time: nil)] }

              it 'should raise an error after timeout' do
                expect { subject }.to raise_error ResourceWaiterError,
                  'AutoScaling Group still performing scaling activities'
              end
            end
          end # #wait_until_no_scaling_activities

          describe '#wait_until_all_instances_running' do
            subject do
              waiter.wait_until_all_instances_running(group, timeout, delay)
            end

            let(:asg_mock) { double('Resources::AutoScaling') }
            let(:ec2_mock) { double('Resources::EC2') }
            let(:group) { double('group', name: 'group') }
            let(:timeout) { 2 }
            let(:delay) { 1 }

            around do |ex|
              EC2.mock(ec2_mock) do
                AutoScaling.mock(asg_mock) { ex.run }
              end
            end

            before do
              allow(asg_mock).to receive(:group).and_return(group)
              allow(group).to receive(:instances).and_return(instances)

              if state_objs.empty?
                allow(ec2_mock).to receive(:instance)
              else
                allow(ec2_mock).to receive(:instance).and_return(*state_objs)
              end
            end

            let(:state_objs) do
              states.map { |s| Struct.new(:state).new(Struct.new(:name).new(s)) }
            end
            let(:states) { [] }
            let(:instances) do
              states.map { |s| double('instance', id: 'abc-1234', state: s) }
            end

            context 'with no instances' do
              it { is_expected.to be_nil }
            end

            context 'with single running instance' do
              let(:states) { ['running'] }
              it { is_expected.to be_nil }
            end

            context 'with multiple instances running' do
              let(:states) { ['running', 'running'] }
              it { is_expected.to be_nil }
            end

            context 'with single instance not running' do
              let(:states) { ['running', 'pendings'] }

              it 'should raise an error after timeout' do
                expect { subject }.to raise_error ResourceWaiterError,
                  'AutoScaling Group has instances not in running state'
              end
            end
          end # #wait_until_all_instances_running
        end # Waiters
      end # AutoScaling
    end # Aws::Resources
  end # Components
end # Podbay