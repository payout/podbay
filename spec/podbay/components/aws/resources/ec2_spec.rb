module Podbay
  module Components
    module Aws::Resources
      RSpec.describe EC2 do
        let(:ec2) { EC2.new }

        def aws_error(error_name)
          ::Aws::EC2::Errors.error_class(error_name).new('','')
        end

        describe '#client' do
          subject { ec2.client }
          it { is_expected.to be_a ::Aws::EC2::Client }
        end # #client

        describe '#vpc_exists?' do
          subject { ec2.vpc_exists?(vpc_id) }

          before { allow(ec2).to receive(:vpc).and_return(vpc) }

          let(:vpc) { double('VPC', vpc_id: vpc_id) }
          let(:vpc_id) { 'vpc-01234567' }

          it { is_expected.to eq true }

          context 'with invalid vpc id' do
            before do
              allow(vpc).to receive(:vpc_id)
                .and_raise(aws_error('InvalidVpcIDNotFound'))
            end

            it { is_expected.to eq false }
          end # with invalid vpc id
        end # #vpc_exists?

        describe '#subnet_exists?' do
          subject { ec2.subnet_exists?(subnet_id) }

          before { allow(ec2).to receive(:subnet).and_return(subnet) }

          let(:subnet) { double('subnet', subnet_id: subnet_id) }
          let(:subnet_id) { 'subnet-abc1234' }

          it { is_expected.to eq true }

          context 'with invalid vpc id' do
            before do
              allow(subnet).to receive(:subnet_id)
                .and_raise(aws_error('InvalidSubnetIDNotFound'))
            end

            it { is_expected.to eq false }
          end
        end # #subnet_exists?

        describe '#security_group_exists?' do
          subject { ec2.security_group_exists?(sg.id) }

          before { allow(ec2).to receive(:security_group).and_return(sg) }

          let(:sg) { double('VPC', id: 'sg-01234567', vpc_id: vpc_id) }
          let(:vpc_id) { 'vpc-01234567' }

          it { is_expected.to eq true }

          context 'with invalid vpc id' do
            before do
              allow(sg).to receive(:vpc_id)
                .and_raise(aws_error('InvalidGroupNotFound'))
            end

            let(:sg) { double('VPC', id: 'sg-01234567') }

            it { is_expected.to eq false }
          end # with invalid vpc id
        end # #security_group_exists?

        describe '#hostname' do
          subject { ec2.hostname(instance_id) }

          let(:instance_id) { 'i-abc1234' }
          let(:instance) { double('instance', private_dns_name: dns_name) }
          let(:dns_name) { 'ip-10-0-3-186.ec2.internal' }

          before do
            allow(ec2).to receive(:instance).with(instance_id)
              .and_return(instance)
          end

          it { is_expected.to eq 'ip-10-0-3-186' }
        end # #hostname

        describe '#add_tags' do
          subject { ec2.add_tags(resource_ids, tags) }

          before { allow(ec2).to receive(:create_tags) }

          after { subject }

          let(:resource_ids) { ['i-abc1234'] }
          let(:tags) { {} }

          context 'with no tags' do
            it 'should call create_tags with the correct args' do
              expect(ec2).to receive(:create_tags).with(
                resources: resource_ids, tags: []
              )
            end
          end

          context 'with tags' do
            let(:tags) { { my_key: 'my_val', another_key: 'another_val' } }

            it 'should call create_tags with the correct args' do
              expect(ec2).to receive(:create_tags).with(
                resources: resource_ids,
                tags: [
                  { key: :my_key, value: 'my_val' },
                  { key: :another_key, value: 'another_val' }
                ]
              )
            end
          end # with tags

          context 'with non-array resource id' do
            let(:resource_ids) { 'i-abc1234' }

            it 'should place single id into an array' do
              expect(ec2).to receive(:create_tags).with(
                resources: [resource_ids], tags: []
              )
            end
          end
        end # #add_tags

        describe '#instance_healthy?', :instance_healthy do
          subject { ec2.instance_healthy?(instance_id, services, elb_names) }

          let(:consul_mock) { double('Podbay::Consul') }
          let(:elb_mock) { double('Resources::ELB') }

          around do |ex|
            Podbay::Consul.mock(consul_mock) do
              ELB.mock(elb_mock) do
                ex.run
              end
            end
          end

          before do
            allow(consul_mock).to receive(:node_healthy?)
              .and_return(node_health)
            allow(ec2).to receive(:hostname).and_return('ip-10-1-2-3')
            allow(elb_mock).to receive(:elbs_healthy?).and_return(elb_health)
          end

          let(:node_health) { true }
          let(:elb_health) { true }
          let(:instance_id) { 'id-abc1234' }
          let(:services) { [] }
          let(:elb_names) { [] }

          context 'with healthy instance' do
            let(:node_health) { true }
            it { is_expected.to eq true }
          end

          context 'with unhealthy instance' do
            let(:node_health) { false }
            it { is_expected.to eq false }
          end

          context 'with static_services' do
            after { subject }

            context 'with a single service' do
              let(:services) { ['test-service'] }

              it 'should perform service health checks' do
                expect(consul_mock).to receive(:node_healthy?)
                  .with('ip-10-1-2-3', ['test-service'])
              end
            end

            context 'with multiple services' do
              let(:services) { ['test-service1', 'test-service2'] }

              it 'should perform service health checks' do
                expect(consul_mock).to receive(:node_healthy?)
                  .with('ip-10-1-2-3', ['test-service1', 'test-service2'])
              end
            end
          end # with static_services

          context 'with elbs' do
            let(:elb_names) { ['elb-1', 'elb-2'] }

            it 'should perform elb health checks' do
              expect(elb_mock).to receive(:elbs_healthy?).with(elb_names)
              subject
            end

            context 'with healthy elb health checks' do
              let(:elb_health) { true }
              it { is_expected.to be true }
            end

            context 'with unhealthy elb health checks' do
              let(:elb_health) { false }
              it { is_expected.to be false }
            end
          end
        end # #instance_healthy?
      end # EC2
    end # Aws::Resources
  end # Components
end # Podbay
