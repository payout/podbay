module Podbay
  class Components::Aws
    RSpec.describe Cluster do
      let(:cluster) { Cluster.new(cluster_name) }
      let(:cluster_name) { 'test-cluster' }
      let(:ec2_mock) { double('Resources::EC2') }
      let(:asg_mock) { double('Resources::AutoScaling') }
      let(:cf_mock) { double('Resources::CloudFormation') }

      around do |ex|
        Resources::EC2.mock(ec2_mock) do
          Resources::CloudFormation.mock(cf_mock) do
            Resources::AutoScaling.mock(asg_mock) do
              ex.run
            end
          end
        end
      end

      before do
        allow(cf_mock).to receive(:stack).with(cluster_name).and_return(stack)
        allow(stack).to receive(:resource).with('VPC').and_return(
          double('VPC Stack Resource', physical_resource_id: vpc_id)
        )

        allow(ec2_mock).to receive(:vpc).with(vpc_id).and_return(vpc)
        allow(ec2_mock).to receive(:vpc_exists?).with(vpc_id)
          .and_return(vpc_exists)
        allow(ec2_mock).to receive(:tags_of).with(vpc).and_return(vpc_tags)

        vpc_tags.each_with_index do |_, i|
          allow(stack).to receive(:resource).with("PrivateRouteTable#{i+1}")
            .and_return(
              double("PrivateRouteTable#{i+1}",
                physical_resource_id: "rt-abc12#{i}")
            )
        end

        allow(stack).to receive(:resource).with("PublicRouteTable")
          .and_return(double('PublicRouteTable',
            physical_resource_id: 'rt-abc1234'))
        allow(vpc).to receive(:subnets).and_return(subnets)
      end

      let(:stack) { double('CF Stack', exists?: stack_exists) }
      let(:stack_exists) { true }
      let(:vpc) { double('VPC', cidr_block: vpc_cidr, id: vpc_id) }
      let(:vpc_id) { 'vpc-abcdef01' }
      let(:vpc_cidr) { '10.0.0.0/16' }
      let(:vpc_exists) { true }
      let(:vpc_tags) do
        azs.each_with_index.map { |az, i| {"az#{i}" => az } }.reduce({}, :merge)
      end
      let(:azs) { ['us-east-1b'] }
      let(:route_tables) do
        vpc_tags.each_with_index.map { |_, i| double("rt-abc123#{i}") }
      end
      let(:public_route_table) { double('rt-abc1234') }
      let(:subnets) do
        (subnet_cidrs + db_subnet_cidrs).each_with_index.map do |cidr, i|
          double("subnet-abc12#{i}", id: "subnet-abc12#{i}", tags: [],
            cidr_block: cidr)
        end
      end
      let(:subnet_cidrs) { ['10.0.1.0/24', '10.0.3.0/24'] }
      let(:db_subnet_cidrs) { [] }

      describe '#new' do
        subject { cluster }

        it 'should set the name' do
          expect(subject.name).to eq cluster_name
        end
      end # #new

      describe '#vpc' do
        subject { cluster.vpc }

        it { is_expected.to eq vpc }

        context 'with missing vpc' do
          let(:vpc_exists) { false }

          it 'should raise an error' do
            expect { subject }.to raise_error MissingResourceError,
              "VPC for cluster 'test-cluster' missing"
          end
        end
      end # #vpc

      describe '#vpc_cidr' do
        subject { cluster.vpc_cidr }
        it { is_expected.to eq vpc_cidr }
      end # #vpc_cidr

      describe '#availability_zones' do
        subject { cluster.availability_zones }

        it { is_expected.to eq ['us-east-1b'] }

        context 'with multiple availability zones' do
          let(:vpc_tags) { { 'az1' => 'us-east-1b', 'az2' => 'us-east-1c' } }
          it { is_expected.to eq ['us-east-1b', 'us-east-1c'] }
        end

        context 'with missing VPC tags' do
          let(:vpc_tags) { {} }
          it 'should raise an error' do
            expect { subject }.to raise_error MissingResourceError,
              'Availability Zone(s) VPC tags missing'
          end
        end

        context 'with out of order tags' do
          let(:vpc_tags) do
            {
              'az2' => 'us-east-1c',
              'az1' => 'us-east-1b'
            }
          end

          it { is_expected.to eq ['us-east-1b', 'us-east-1c'] }
        end # with out of order tags
      end # #availability_zones

      describe '#public_route_table' do
        subject { cluster.public_route_table }
        before do
          allow(ec2_mock).to receive(:route_table)
            .and_return(public_route_table)
        end

        it { is_expected.to eq public_route_table }
      end # #public_route_table

      describe '#private_route_tables' do
        subject { cluster.private_route_tables }
        before do
          allow(ec2_mock).to receive(:route_tables).and_return(route_tables)
        end

        it { is_expected.to eq route_tables }

        context 'with multiple route tables' do
          let(:vpc_tags) { { 'az1' => 'us-east-1b', 'az2' => 'us-east-1c' } }
          it { is_expected.to eq route_tables }
        end
      end # #private_route_tables

      describe '#stack' do
        subject { cluster.stack }

        it { is_expected.to eq stack }

        context 'with missing stack' do
          let(:stack_exists) { false }

          it 'should raise an error' do
            expect { subject }.to raise_error MissingResourceError,
              "CloudFormation stack 'test-cluster' missing"
          end
        end
      end # #stack

      describe '#create_subnets' do
        subject { cluster.create_subnets(count, dmz, mask, tags) }

        before do
          allow(ec2_mock).to receive(:create_subnet) do |params|
            double('Subnet',
              id: "subnet-#{SecureRandom.hex(4)}",
              cidr_block: params[:cidr_block],
              availability_zone: params[:availability_zone],
              delete: true
            )
          end
          allow(ec2_mock).to receive(:add_tags)
          allow(ec2_mock).to receive(:subnet_exists?).and_return(true)
        end

        let(:count) { 1 }
        let(:dmz) { false }
        let(:mask) { 24 }
        let(:tags) { {} }
        let(:subnet_cidrs) { [] }

        it 'should add the cluster tag by default' do
          expect(ec2_mock).to receive(:add_tags).with(
            [/\Asubnet-.*\z/], { 'podbay:cluster' => 'test-cluster' }
          )
          subject
        end

        context 'with no subnets available' do
          let(:subnet_cidrs) { (1..255).map { |i| "10.0.#{i}.0/24" } }

          it 'should raise an error' do
            expect { subject }.to raise_error RuntimeError,
              'no IPs available for subnet'
          end
        end

        context 'with no previous subnets' do
          let(:subnet_cidrs) { [] }

          it 'should create a subnet with the first available cidr' do
            expect(ec2_mock).to receive(:create_subnet).with(
              cidr_block: '10.0.1.0/24',
              availability_zone: 'us-east-1b',
              vpc_id: 'vpc-abcdef01'
            )

            subject
          end
        end

        context 'with previous subnets' do
          let(:subnet_cidrs) { ['10.0.1.0/24', '10.0.3.0/24'] }

          it 'should create a subnet with the first available cidr' do
            expect(ec2_mock).to receive(:create_subnet).with(
              cidr_block: '10.0.5.0/24',
              availability_zone: 'us-east-1b',
              vpc_id: 'vpc-abcdef01'
            )

            subject
          end
        end

        context 'with too few availability zones' do
          let(:azs) { [] }

          it 'should raise an error' do
            expect { subject }.to raise_error Podbay::MissingResourceError,
              'Availability Zone(s) VPC tags missing'
          end
        end

        context 'with count=2' do
          let(:count) { 2 }
          let(:azs) { ['us-east-1b', 'us-east-1c'] }

          it 'should create 2 subnets' do
            expect(ec2_mock).to receive(:create_subnet).with(
              cidr_block: '10.0.1.0/24',
              availability_zone: 'us-east-1b',
              vpc_id: 'vpc-abcdef01'
            )
            expect(ec2_mock).to receive(:create_subnet).with(
              cidr_block: '10.0.3.0/24',
              availability_zone: 'us-east-1c',
              vpc_id: 'vpc-abcdef01'
            )

            subject
          end
        end

        context 'with count=0' do
          let(:count) { 0 }

          it 'should not create any subnets' do
            expect(ec2_mock).not_to receive(:create_subnet)
          end
        end

        context 'with dmz=true' do
          let(:dmz) { true }
          let(:subnet_cidrs) { [] }

          it 'should create a subnet with even cidrs' do
            expect(ec2_mock).to receive(:create_subnet).with(
              cidr_block: '10.0.0.0/24',
              availability_zone: 'us-east-1b',
              vpc_id: 'vpc-abcdef01'
            )

            subject
          end
        end

        context 'with mask=28' do
          let(:mask) { 28 }

          after { subject }

          context 'with previous /24 subnets' do
            let(:subnet_cidrs) { ['10.0.1.0/24', '10.0.3.0/24'] }

            it 'should create subnets in the next available octet' do
              expect(ec2_mock).to receive(:create_subnet).with(
                cidr_block: '10.0.5.0/28',
                availability_zone: 'us-east-1b',
                vpc_id: vpc.id
              ).once
            end
          end

          context 'with previous /28 subnets' do
            let(:db_subnet_cidrs) { ['10.0.1.0/28', '10.0.1.16/28'] }

            it 'should create next available subnet' do
              expect(ec2_mock).to receive(:create_subnet).with(
                cidr_block: '10.0.1.32/28',
                availability_zone: 'us-east-1b',
                vpc_id: vpc.id
              ).once
            end

            context 'with 1 subnet available in /28 octet' do
              let(:db_subnet_cidrs) do
                ['10.0.1.0/28', '10.0.1.16/28', '10.0.1.32/28', '10.0.1.48/28',
                 '10.0.1.64/28', '10.0.1.80/28', '10.0.1.96/28', '10.0.1.112/28',
                 '10.0.1.128/28', '10.0.1.144/28', '10.0.1.160/28',
                 '10.0.1.176/28', '10.0.1.192/28', '10.0.1.208/28']
              end

              it 'should create next available subnets' do
                expect(ec2_mock).to receive(:create_subnet).with(
                  cidr_block: '10.0.1.224/28',
                  availability_zone: 'us-east-1b',
                  vpc_id: vpc.id
                ).once
              end
            end

            context 'with no subnets available in /28 octet' do
              let(:db_subnet_cidrs) do
                ['10.0.1.0/28', '10.0.1.16/28', '10.0.1.32/28', '10.0.1.48/28',
                 '10.0.1.64/28', '10.0.1.80/28', '10.0.1.96/28', '10.0.1.112/28',
                 '10.0.1.128/28', '10.0.1.144/28', '10.0.1.160/28',
                 '10.0.1.176/28', '10.0.1.192/28', '10.0.1.208/28',
                 '10.0.1.224/28', '10.0.1.240/28']
              end

              it 'should create next available subnets with new octet' do
                expect(ec2_mock).to receive(:create_subnet).with(
                  cidr_block: '10.0.3.0/28',
                  availability_zone: 'us-east-1b',
                  vpc_id: vpc.id
                ).once
              end
            end
          end # with previous /28 subnets
        end # with mask=28

        context 'with custom tags' do
          let(:tags) { { tag_key: 'tag_val' } }

          it 'should set the tags to the subnets' do
            expect(ec2_mock).to receive(:add_tags).with(
              [/\Asubnet-.*\z/],
              {
                'podbay:cluster' => 'test-cluster',
                tag_key: 'tag_val'
              }
            )
            subject
          end
        end
      end # #create_subnets

      describe '#subnets' do
        subject { cluster.subnets(filters) }
        let(:filters) { [{ name: 'tag-key', values: ['podbay:database'] }] }

        it { is_expected.to eq subnets }

        it 'should pass in the filters' do
          expect(vpc).to receive(:subnets).with(filters: filters)
          subject
        end

        context 'without filters arg' do
          subject { cluster.subnets }
          it { is_expected.to eq subnets }

          it 'should default filters to []' do
            expect(vpc).to receive(:subnets).with(filters: [])
            subject
          end
        end
      end # #subnets

      describe '#id_of' do
        subject { cluster.id_of(id) }

        let(:id) { 'resource-id' }

        it 'should call stack resource' do
          expect(stack).to receive(:resource).with(id)
            .and_return(double('stack', physical_resource_id: 'id'))
          subject
        end
      end # #id_of

      describe '#formatted_name' do
        subject { cluster.formatted_name }

        context 'with cluster="my cluster"' do
          let(:cluster_name) { 'my cluster' }
          it { is_expected.to eq 'my-cluster' }
        end

        context 'with cluster="myCLUSTER"' do
          let(:cluster_name) { 'myCLUSTER' }
          it { is_expected.to eq 'mycluster' }
        end

        context 'with cluster="my_cluster"' do
          let(:cluster_name) { 'my_cluster' }
          it { is_expected.to eq 'my-cluster' }
        end

        context 'with cluster="clu!@#$%^%&*()ster"' do
          let(:cluster_name) { 'clu!@#$%^%&*()ster' }
          it { is_expected.to eq 'cluster' }
        end

        context 'with cluster="my cluster_name"' do
          let(:cluster_name) { 'my cluster_name' }
          it { is_expected.to eq 'my-cluster-name' }
        end

        context 'with cluster="my CLu!@#$%^%&*()ster_name"' do
          let(:cluster_name) { 'my CLu!@#$%^%&*()ster_name' }
          it { is_expected.to eq 'my-cluster-name' }
        end
      end # #formatted_name

      describe '#groups' do
        subject { cluster.groups }

        before do
          allow(asg_mock).to receive(:groups).and_return(groups)
        end

        let(:groups) do
          group_tags.map { |tags| double(data: double(tags: tags)) }
        end

        context 'with no groups in cluster' do
          let(:group_tags) { [] }
          it { is_expected.to eq [] }

          context 'with groups in other clusters' do
            let(:group_tags) do
              [
                [double(key: 'podbay:cluster', value: 'another-cluster')],
                [double(key: 'podbay:cluster', value: 'another-cluster')],
                [double(key: 'podbay:cluster', value: 'different-cluster')]
              ]
            end

            it { is_expected.to eq [] }
          end

          context 'with no podbay:cluster tags' do
            let(:group_tags) do
              [
                [double(key: 'podbay:role', value: 'server')]
              ]
            end

            it { is_expected.to eq [] }
          end
        end

        context 'with group in cluster' do
          let(:group_tags) do
            [
              [double(key: 'podbay:cluster', value: 'another-cluster')],
              [double(key: 'podbay:cluster', value: cluster_name)],
              [double(key: 'podbay:cluster', value: 'different-cluster')]
            ]
          end

          it 'should return the groups within the cluster' do
            expect(subject.length).to eq 1
            subject.each do |g|
              expect(g.data.tags.first.value).to eq cluster_name
            end
          end
        end # with group in cluster

        context 'with multiple groups in cluster' do
          let(:group_tags) do
            [
              [double(key: 'podbay:cluster', value: 'another-cluster')],
              [double(key: 'podbay:cluster', value: cluster_name)],
              [double(key: 'podbay:cluster', value: 'different-cluster')],
              [double(key: 'podbay:cluster', value: cluster_name)]
            ]
          end

          it 'should return the groups within the cluster' do
            expect(subject.length).to eq 2
            subject.each do |g|
              expect(g.data.tags.first.value).to eq cluster_name
            end
          end
        end # with multiple groups in cluster
      end # #groups

      describe '#asg_of_group' do
        subject { cluster.asg_of_group(name) }
        let(:name) { 'group-name' }

        before do
          allow(ec2_mock).to receive(:instances).with(filters: [
            { name: 'tag:podbay:cluster', values: [cluster_name] },
            { name: 'tag:podbay:group', values: [name] },
            { name: 'instance-state-name', values: ['running'] }
          ]).and_return(instances)

          allow(asg_mock).to receive(:instances).with(instance_ids:
            instances.map(&:id)).and_return(instances)
        end

        let(:instances) do
          [
            double('instance', id: 'i-abc1234', group: asg, group_name:'gr-abc')
          ]
        end
        let(:asg) { double('asg') }

        it { is_expected.to eq asg }

        context 'with no asg found' do
          let(:instances) { [] }
          it { is_expected.to eq nil }
        end

        context 'with more than one asg found' do
          let(:instances) do
            [
              double('instance',
                id: 'i-abc1234',
                group: asg,
                group_name:'gr-abc'
              ),
              double('instance',
                id: 'i-abc1234',
                group: asg,
                group_name:'gr-123'
              )
            ]
          end

          it 'should raise an error' do
            expect { subject }.to raise_error PodbayGroupError,
              'More than 1 AutoScaling Group found: ["gr-abc", "gr-123"].'
          end
        end
      end # #asg_of_group

      describe '#subnets_of_group' do
        subject { cluster.subnets_of_group(name) }
        let(:name) { 'group-name' }

        it 'should send the appropriate request' do
          expect(vpc).to receive(:subnets).with(filters: [
            { name: 'tag:podbay:group', values: [name] }
          ])

          subject
        end
      end # #subnets_of_group
    end # Cluster
  end # Components::Aws
end # Podbay