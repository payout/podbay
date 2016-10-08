module Podbay
  module Components
    module Aws::Resources
      RSpec.describe ELB do
        let(:elb) { ELB.new }

        def aws_error(error_name)
          ::Aws::ElasticLoadBalancing::Errors.error_class(error_name).new('','')
        end

        it 'should send missing methods to the client' do
          expect(elb).to receive(:client)
            .and_return(double('client', test_method: 'test'))
          expect(elb.test_method).to eq 'test'
        end

        describe '#client' do
          subject { elb.client }

          it { is_expected.to be_a ::Aws::ElasticLoadBalancing::Client }
        end # #client

        describe '#elb_exists?' do
          subject { elb.elb_exists?(elb_name) }

          before do
            allow(elb).to receive(:describe_load_balancers)
              .and_return(load_balancer)
          end

          let(:load_balancer) { double('ELB') }
          let(:elb_name) { 'gr-abc123' }

          it { is_expected.to eq true }

          context 'with invalid elb name' do
            before do
              allow(elb).to receive(:describe_load_balancers)
                .and_raise(aws_error('LoadBalancerNotFound'))
            end

            it { is_expected.to eq false }
          end # with invalid elb name
        end # #elb_exists?

        describe '#elbs_healthy?' do
          subject { elb.elbs_healthy?(elb_names) }

          before { allow(elb).to receive(:wait_until) }

          let(:elb_names) { ['elb-1'] }
          let(:is_healthy) { true }

          after { subject }

          context 'with single ELB' do
            let(:elb_names) { ['elb-1'] }

            it 'should wait for the instances to be in service' do
              elb_names.each do |name|
                expect(elb).to receive(:wait_until)
                  .with(:instance_in_service, load_balancer_name: name)
              end
            end

            it { is_expected.to eq true }

            context 'with ELB health check failing' do
              before do
                allow(elb).to receive(:wait_until).and_raise(
                  ::Aws::Waiters::Errors::TooManyAttemptsError.new(20)
                )
              end

              it { is_expected.to eq false }
            end
          end # with single ELB

          context 'with multiple ELBs' do
            let(:elb_names) { ['elb-1', 'elb-2'] }

            it 'should wait for all elbs to show instances in service' do
              elb_names.each do |name|
                expect(elb).to receive(:wait_until)
                  .with(:instance_in_service, load_balancer_name: name)
              end
            end

            it { is_expected.to eq true }

            context 'with 1 ELB health check failure' do
              before do
                allow(elb).to receive(:wait_until)
                  .with(:instance_in_service, load_balancer_name: 'elb-2')
                  .and_raise(
                    ::Aws::Waiters::Errors::TooManyAttemptsError.new(20)
                  )
              end

              it { is_expected.to eq false }
            end
          end # with multiple ELBs
        end
      end # ELB
    end # Aws::Resources
  end # Components
end # Podbay
