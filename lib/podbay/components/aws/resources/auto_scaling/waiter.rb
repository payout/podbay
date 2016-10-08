module Podbay
  module Components
    module Aws::Resources
      class AutoScaling
        class Waiter
          include Mixins::Mockable

          def wait_until_group_has_size(group, size, timeout = 300, delay = 15)
            msg = "AutoScaling Group did not reach desired size of #{size}"
            _wait_until(group, msg, timeout, delay) do |g|
              g.instances.to_a.size == size
            end
          end

          def wait_until_no_scaling_activities(group, timeout = 300, delay = 15)
            msg = 'AutoScaling Group still performing scaling activities'
            _wait_until(group, msg, timeout, delay) do |g|
              g.activities.map(&:end_time).none? { |et| et.nil? }
            end
          end

          def wait_until_all_instances_running(group, timeout = 300, delay = 15)
            msg = 'AutoScaling Group has instances not in running state'
            _wait_until(group, msg, timeout, delay) do |g|
              g.instances.to_a.all? do |i|
                EC2.instance(i.id).state.name == 'running'
              end
            end
          end

          private

          def _wait_until(group, failure_msg, timeout, delay)
            (timeout / delay).times do
              group = AutoScaling.group(group.name)
              return if yield(group)
              print '.'
              sleep(delay)
            end

            fail ResourceWaiterError, failure_msg
          end
        end # Waiter
      end # AutoScaling
    end # Aws::Resources
  end # Components
end # Podbay