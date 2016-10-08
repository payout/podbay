module Podbay
  module Components
    RSpec.describe Aws do
      let(:aws) { Aws.new(options) }
      let(:options) do
        {}.tap do |o|
          o.merge!(cluster: cluster) if cluster
        end
      end

      let(:cluster) { 'test-cluster' }

      describe '#bootstrap' do
        subject { aws.bootstrap(params) }

        let(:params) do
          {}.tap do |p|
            p.merge!(role: role_val) if role_val
            p.merge!(dmz: dmz_val) if dmz_val
            p.merge!(ami: ami_val) if ami_val
            p.merge!(size: size_val) if size_val
            p.merge!(instance_type: instance_type_val) if instance_type_val
            p.merge!(key_pair: key_pair_val) if key_pair_val
            p.merge!(discovery_mode: discovery_mode_val) if discovery_mode_val
            p.merge!(elb: elb_params) if elb_params
            p.merge!(modules: modules_params) if modules_params
          end
        end

        let(:role_val) { nil }
        let(:dmz_val) { nil }
        let(:ami_val) { nil }
        let(:size_val) { nil }
        let(:instance_type_val) { nil }
        let(:key_pair_val) { nil }
        let(:discovery_mode_val) { nil }
        let(:elb_params) { nil }
        let(:modules_params) { nil }
        let(:servers_exist_resp) { nil }

        let(:ec2_mock) { double('Resources::EC2') }
        let(:iam_mock) { double('Resources::IAM') }
        let(:elb_mock) { double('Resources::ELB') }
        let(:asg_mock) { double('Resources::AutoScaling') }
        let(:cluster_mock) { double('Cluster') }

        around do |ex|
          aws.mock_cluster(cluster_mock) do
            Aws::Resources::EC2.mock(ec2_mock) do
              Aws::Resources::IAM.mock(iam_mock) do
                Aws::Resources::ELB.mock(elb_mock) do
                  Aws::Resources::AutoScaling.mock(asg_mock) do
                    ex.run
                  end
                end
              end
            end
          end
        end

        before do
          allow(cluster_mock).to receive(:servers_exist?)
            .and_return(servers_exist_resp)
          allow(cluster_mock).to receive(:config_bucket)
            .and_return('config_bucket')
          allow(cluster_mock).to receive(:podbay_bucket)
            .and_return('podbay_bucket')
          allow(aws).to receive(:setup_gossip_encryption)
          allow(aws).to receive(:setup_backup_key)

          allow(cluster_mock).to receive(:vpc).and_return(aws_vpc)
          allow(ec2_mock).to receive(:vpc_exists?).and_return(true)
          allow(cluster_mock).to receive(:formatted_name).and_return(cluster)

          allow(ec2_mock).to receive(:tags_of).with(aws_vpc)
            .and_return(aws_vpc_tags)

          allow(cluster_mock).to receive(:availability_zones).and_return(azs)
          allow(cluster_mock).to receive(:create_subnets).and_return(
            azs.each_with_index.map do |az, i|
              double('Subnet',
                id: "subnet-#{SecureRandom.hex(4)}",
                availability_zone: az
              )
            end
          )

          allow(cluster_mock).to receive(:id_of).with('ClientSecurityGroup')
            .and_return(client_sg_id)

          allow(ec2_mock).to receive(:security_group)
            .with(client_sg_id).and_return(client_sg)

          allow(ec2_mock).to receive(:security_group_exists?).with(client_sg_id)
            .and_return(client_sg_exists)

          allow(cluster_mock).to receive(:region).and_return('us-east-1')
          allow(cluster_mock).to receive(:id_of).with('DMZClientSecurityGroup')
            .and_return(dmz_client_sg_id)

          allow(ec2_mock).to receive(:security_group)
            .with(dmz_client_sg_id).and_return(dmz_client_sg)

          allow(ec2_mock).to receive(:security_group_exists?)
            .with(dmz_client_sg_id)
            .and_return(dmz_client_sg_exists)

          allow(cluster_mock).to receive(:vpc_cidr).and_return(aws_vpc_cidr)
          allow(cluster_mock).to receive(:private_route_tables)
            .and_return(private_route_tables)
          allow(cluster_mock).to receive(:public_route_table)
            .and_return(public_route_table)

          allow(cluster_mock).to receive(:id_of).with('ServerSecurityGroup')
            .and_return(server_sg_id)

          allow(ec2_mock).to receive(:security_group)
            .with(server_sg_id).and_return(server_sg)

          allow(ec2_mock).to receive(:security_group_exists?).with(server_sg_id)
            .and_return(server_sg_exists)

          allow(cluster_mock).to receive(:id_of)
            .with('PodbayClientInstanceProfile').and_return(instance_profile_id)
          allow(cluster_mock).to receive(:id_of)
            .with('PodbayServerInstanceProfile').and_return(instance_profile_id)

          allow(iam_mock).to receive(:instance_profile)
            .with(instance_profile_id).and_return(instance_profile)

          allow(asg_mock).to receive(:create_launch_configuration)
            .and_return(launch_config)

          allow(cluster_mock).to receive(:id_of).with('DMZELBSecurityGroup')
            .and_return(elb_sg_id)

          allow(ec2_mock).to receive(:security_group)
            .with(elb_sg_id).and_return(elb_sg)

          allow(ec2_mock).to receive(:security_group_exists?).with(elb_sg.id)
            .and_return(elb_sg_exists)

          allow(elb_mock).to receive(:create_load_balancer)
          allow(elb_mock).to receive(:set_load_balancer_policies_of_listener)
          allow(elb_mock).to receive(:modify_load_balancer_attributes)
          allow(elb_mock).to receive(:configure_health_check)

          allow(asg_mock).to receive(:create_group).and_return(asg)
        end

        let(:aws_vpc) do
          double('VPC', cidr_block: aws_vpc_cidr, id: aws_vpc_id)
        end
        let(:aws_vpc_cidr) { '10.0.0.0/16' }
        let(:aws_vpc_id) { 'vpc-abcdef01' }
        let(:aws_vpc_tags) do
          azs.each_with_index.map { |az, i| {"az#{i}" => az } }
            .reduce({}, :merge)
        end
        let(:azs) { ['us-east-1b'] }
        let(:private_route_tables) do
          azs.map do |az|
            double('rt-abc1234',
              tags: [
                Struct.new(:key, :value).new('AvailabilityZone', az)
              ],
              associate_with_subnet: true
            )
          end
        end
        let(:public_route_table) do
          double('rt-abc1234', associate_with_subnet: true)
        end
        let(:client_sg_id) { 'sg-01234567' }
        let(:client_sg) { double('Client Security Group', id: client_sg_id) }
        let(:client_sg_exists) { true }
        let(:dmz_client_sg_id) { 'sg-123456' }
        let(:dmz_client_sg) do
          double('DMZ Client Security Group', id: dmz_client_sg_id)
        end
        let(:dmz_client_sg_exists) { true }
        let(:server_sg_id) { 'sg-abcdefgh' }
        let(:server_sg) { double('Server Security Group', id: server_sg_id) }
        let(:server_sg_exists) { true }
        let(:elb_sg_id) { 'sg-11234567' }
        let(:elb_sg) { double('ELB Security Group', id: elb_sg_id) }
        let(:elb_sg_exists) { true }
        let(:elb) { double('ELB') }
        let(:instance_profile_id) do
          "#{cluster}-PodbayInstanceProfile-1JW2ZRDFDUBN5"
        end
        let(:instance_profile) do
          double('Instance Profile',
            exists?: instance_profile_exists,
            arn: "arn:aws:iam::902170953588:instance-profile/#{instance_profile_id}"
          )
        end
        let(:instance_profile_exists) { true }
        let(:launch_config) { double('Launch Configuration', name: 'lc_name') }
        let(:asg) { double('Auto Scaling Group', name: 'gr-01234567') }

        def gen_user_data(podbay_conf)
          Base64.encode64(
            <<-BASH
#!/bin/bash
echo '#{podbay_conf.to_json}' > /etc/podbay.conf
            BASH
          )
        end

        context 'with role=client' do
          let(:role_val) { 'client' }

          context 'with servers existing' do
            let(:servers_exist_resp) { true }

            context 'with valid ami' do
              let(:ami_val) { 'ami-abc123' }

              it 'should use PodbayClientInstanceProfile' do
                expect(cluster_mock).to receive(:id_of)
                  .with('PodbayClientInstanceProfile')
                subject
              end

              it 'should not use PodbayServerInstanceProfile' do
                expect(cluster_mock).not_to receive(:id_of)
                  .with('PodbayServerInstanceProfile')
                subject
              end
            end # with valid ami
          end # with servers existing
        end # with role=client

        context 'with valid params' do
          let(:role_val) { 'client' }
          let(:ami_val) { 'ami-abc123' }
          let(:dmz_val) { 'false' }

          context 'with servers existing' do
            let(:servers_exist_resp) { true }

            it 'should create a subnet' do
              expect(cluster_mock).to receive(:create_subnets).with(
                1, false, 24, 'podbay:group' => a_string_matching(/\Agr-.*\z/)
              )

              subject
            end

            it 'should associate the subnet to its private route table' do
              expect(private_route_tables.length).to eq 1
              expect(private_route_tables.first).to receive(:associate_with_subnet).with(
                subnet_id: a_string_matching(/\Asubnet-[A-Za-z0-9]+\z/)
              )

              subject
            end

            context 'with default setup' do
              after { subject }

              it 'should create a launch configuration using defaults' do
                expect(asg_mock).to receive(:create_launch_configuration)
                  .with(
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    image_id: "ami-abc123",
                    iam_instance_profile: "arn:aws:iam::902170953588:instance-profile/test-cluster-PodbayInstanceProfile-1JW2ZRDFDUBN5",
                    associate_public_ip_address: "false",
                    security_groups: ["sg-01234567"],
                    instance_type: 't2.small',
                    user_data: gen_user_data(
                      consul: {
                        role: 'client',
                        cluster: 'test-cluster',
                        discovery_mode: 'awstags',
                        gossip_key_file: "s3://config_bucket/gossip_key",
                        storage_location: "s3://podbay_bucket"
                      }
                    )
                  )
              end

              it 'should create an autoscaling group using defaults' do
                expect(asg_mock).to receive(:create_group)
                  .with(
                    auto_scaling_group_name: a_string_matching(/\Agr-.*\z/),
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    min_size: 2,
                    max_size: 2,
                    desired_capacity: 2,
                    health_check_grace_period: "300",
                    health_check_type: "EC2",
                    vpc_zone_identifier: a_string_matching(/\Asubnet-.*\z/),
                    tags: [
                      {
                        key: 'podbay:cluster',
                        value: 'test-cluster',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:group',
                        value: a_string_matching(/\Agr-[A-Za-z0-9]+\z/),
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:role',
                        value: 'client',
                        propagate_at_launch: true
                      }
                    ]
                  )
              end
            end # with default setup

            context 'with custom params' do
              after { subject }

              let(:size_val) { 4 }
              let(:key_pair_val) { 'key_pair_name' }
              let(:instance_type_val) { 'm3.medium' }

              it 'should create a launch configuration using custom params' do
                expect(asg_mock).to receive(:create_launch_configuration)
                  .with(
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    image_id: "ami-abc123",
                    iam_instance_profile: "arn:aws:iam::902170953588:instance-profile/test-cluster-PodbayInstanceProfile-1JW2ZRDFDUBN5",
                    associate_public_ip_address: "false",
                    security_groups: ["sg-01234567"],
                    instance_type: 'm3.medium',
                    user_data: gen_user_data(
                      consul: {
                        role: 'client',
                        cluster: 'test-cluster',
                        expect: 4,
                        discovery_mode: 'awstags',
                        gossip_key_file: "s3://config_bucket/gossip_key",
                        storage_location: "s3://podbay_bucket"
                      }
                    ),
                    key_name: 'key_pair_name'
                  )
              end

              it 'should create an autoscaling group using custom params' do
                expect(asg_mock).to receive(:create_group)
                  .with(
                    auto_scaling_group_name: a_string_matching(/\Agr-.*\z/),
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    min_size: 4,
                    max_size: 4,
                    desired_capacity: 4,
                    health_check_grace_period: "300",
                    health_check_type: "EC2",
                    vpc_zone_identifier: a_string_matching(/\Asubnet-.*\z/),
                    tags: [
                      {
                        key: 'podbay:cluster',
                        value: 'test-cluster',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:group',
                        value: a_string_matching(/\Agr-[A-Za-z0-9]+\z/),
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:role',
                        value: 'client',
                        propagate_at_launch: true
                      }
                    ]
                  )
              end
            end # with custom params

            context 'with dmz=true' do
              let(:dmz_val) { 'true' }
              let(:elb_params) { { ssl_certificate_arn: 'ssl_certificate_arn' } }

              it 'should use the DMZClientSecurityGroup' do
                expect(asg_mock).to receive(:create_launch_configuration)
                  .with(a_hash_including(security_groups: [dmz_client_sg_id]))
                subject
              end

                context 'with missing dmz client security group' do
                  let(:dmz_client_sg_exists) { false }

                  it 'should raise an error' do
                    expect { subject }.to raise_error MissingResourceError,
                      'security group for "DMZClientSecurityGroup" missing'
                  end
                end

              context 'without ELB params' do
                let(:elb_params) { nil }

                it 'should not create an ELB' do
                  expect(elb_mock).not_to receive(:create_load_balancer)
                  subject
                end
              end # without elb params

              context 'with missing ELB security group' do
                let(:elb_sg_exists) { false }

                it 'should raise an error' do
                  expect { subject }.to raise_error MissingResourceError,
                    'Security Group "DMZELBSecurityGroup" missing'
                end
              end

              context 'with valid setup' do
                after { subject }

                context 'with default ELB values' do
                  it 'should create a subnet in the dmz' do
                    expect(cluster_mock).to receive(:create_subnets).with(
                      1, true, 24,
                      'podbay:group' => a_string_matching(/\Agr-.*\z/)
                    )
                  end

                  it 'should associate the subnet to the public route table' do
                    expect(public_route_table).to receive(:associate_with_subnet)
                      .with(
                        subnet_id: a_string_matching(/\Asubnet-[A-Za-z0-9]+\z/)
                      )
                  end

                  it 'should create a load balancer' do
                    expect(elb_mock).to receive(:create_load_balancer).with(
                      load_balancer_name: a_string_matching(/\Agr-.*\z/),
                      listeners: [
                        {
                          protocol: "HTTP",
                          load_balancer_port: 80,
                          instance_protocol: "HTTP",
                          instance_port: 3001
                        },{
                          protocol: "HTTPS",
                          load_balancer_port: 443,
                          instance_protocol: "HTTP",
                          instance_port: 3001,
                          ssl_certificate_id: "ssl_certificate_arn"
                        }
                      ],
                      subnets: [a_string_matching(/\Asubnet-.+\z/)],
                      security_groups: ["sg-11234567"],
                      tags: [
                        {
                          key: "podbay:cluster",
                          value: "test-cluster" },
                        {
                          key: "podbay:group",
                          value: a_string_matching(/\Agr-.*\z/)
                        }
                      ]
                    )
                  end

                  it 'should create a default health check' do
                    expect(elb_mock).to receive(:configure_health_check).with(
                      load_balancer_name: a_string_matching(/\Agr-.*\z/),
                      health_check: {
                        target: 'tcp:3001',
                        interval: 30,
                        timeout: 3,
                        healthy_threshold: 2,
                        unhealthy_threshold: 2
                      }
                    )
                  end

                  it 'should set the default load balancer policies' do
                    expect(elb_mock).to receive(
                      :set_load_balancer_policies_of_listener
                    ).with(
                      load_balancer_name: a_string_matching(/\Agr-.*\z/),
                      load_balancer_port: 443,
                      policy_names: ['ELBSecurityPolicy-2015-05']
                    )
                  end

                  it 'should set the default load balancer attributes' do
                    expect(elb_mock).to receive(:modify_load_balancer_attributes)
                      .with(
                        load_balancer_name: a_string_matching(/\Agr-.*\z/),
                        load_balancer_attributes: {
                          cross_zone_load_balancing: {
                            enabled: true
                          },
                          connection_draining: {
                            enabled: true,
                            timeout: 300
                          },
                          connection_settings: {
                            idle_timeout: 60
                          }
                        }
                      )
                  end

                  it 'should create a valid ASG linked to the ELB' do
                    expect(asg_mock).to receive(:create_group)
                      .with(
                        auto_scaling_group_name: a_string_matching(/\Agr-.*\z/),
                        launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                        min_size: 2,
                        max_size: 2,
                        desired_capacity: 2,
                        health_check_grace_period: "300",
                        health_check_type: "ELB",
                        vpc_zone_identifier: a_string_matching(/\Asubnet-.*\z/),
                        load_balancer_names: [ a_string_matching(/\Agr-.*\z/) ],
                        tags: [
                          {
                            key: 'podbay:cluster',
                            value: 'test-cluster',
                            propagate_at_launch: true
                          },
                          {
                            key: 'podbay:group',
                            value: a_string_matching(/\Agr-[A-Za-z0-9]+\z/),
                            propagate_at_launch: true
                          },
                          {
                            key: 'podbay:role',
                            value: 'client',
                            propagate_at_launch: true
                          }
                        ]
                      )
                  end
                end # with default ELB values

                context 'with custom ELB values' do
                  let(:elb_params) do
                    {
                      ssl_certificate_arn: 'ssl_certificate_arn',
                      target: '/v1/health_check',
                      interval: 10,
                      timeout: 5,
                      healthy_threshold: 4,
                      unhealthy_threshold: 4
                    }
                  end

                  it 'should create a custom health check' do
                    expect(elb_mock).to receive(:configure_health_check).with(
                      load_balancer_name: a_string_matching(/\Agr-.*\z/),
                      health_check: {
                        target: 'http:3001/v1/health_check',
                        interval: 10,
                        timeout: 5,
                        healthy_threshold: 4,
                        unhealthy_threshold: 4
                      }
                    )
                  end
                end # with custom ELB values
              end # with valid setup
            end # with dmz=true

            context 'with single static service' do
              let(:modules_params) { { static_services: ['service_name1'] } }
              after { subject }

              it 'should add tags for the modules / static_services' do
                expect(asg_mock).to receive(:create_group)
                  .with(a_hash_including(
                    tags: [
                      {
                        key: 'podbay:cluster',
                        value: 'test-cluster',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:group',
                        value: a_string_matching(/\Agr-[A-Za-z0-9]+\z/),
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:role',
                        value: 'client',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:modules:static_services',
                        value: 'service_name1',
                        propagate_at_launch: true
                      }
                    ]
                  ))
              end

              it 'should create the correct launch configuration' do
                expect(asg_mock).to receive(:create_launch_configuration)
                  .with(
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    image_id: "ami-abc123",
                    iam_instance_profile: "arn:aws:iam::902170953588:instance-profile/test-cluster-PodbayInstanceProfile-1JW2ZRDFDUBN5",
                    associate_public_ip_address: "false",
                    security_groups: ["sg-01234567"],
                    instance_type: 't2.small',
                    user_data: gen_user_data(
                      static_services: ['service_name1'],
                      consul: {
                        role: 'client',
                        cluster: 'test-cluster',
                        discovery_mode: 'awstags',
                        gossip_key_file: "s3://config_bucket/gossip_key",
                        storage_location: "s3://podbay_bucket"
                      }
                    )
                  )
              end
            end # with single static service

            context 'with multiple static services' do
              let(:modules_params) do
                {
                  static_services: ['service_name1','service_name2']
                }
              end

              after { subject }

              it 'should create the correct launch configuration' do
                expect(asg_mock).to receive(:create_launch_configuration)
                  .with(
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    image_id: "ami-abc123",
                    iam_instance_profile: 'arn:aws:iam::902170953588:' \
                      'instance-profile/test-cluster-PodbayInstanceProfile-' \
                      '1JW2ZRDFDUBN5',
                    associate_public_ip_address: "false",
                    security_groups: ["sg-01234567"],
                    instance_type: 't2.small',
                    user_data: gen_user_data(
                      static_services: ['service_name1', 'service_name2'],
                      consul: {
                        role: 'client',
                        cluster: 'test-cluster',
                        discovery_mode: 'awstags',
                        gossip_key_file: "s3://config_bucket/gossip_key",
                        storage_location: "s3://podbay_bucket"
                      }
                    )
                  )
              end

              it 'should add tags for the modules / static_services' do
                expect(asg_mock).to receive(:create_group)
                  .with(a_hash_including(
                    tags: [
                      {
                        key: 'podbay:cluster',
                        value: 'test-cluster',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:group',
                        value: a_string_matching(/\Agr-[A-Za-z0-9]+\z/),
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:role',
                        value: 'client',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:modules:static_services',
                        value: 'service_name1,service_name2',
                        propagate_at_launch: true
                      }
                    ]
                  ))
              end
            end # with multiple static services

            context 'with registrar disabled' do
              let(:modules_params) { { registrar: 'off' } }
              after { subject }

              it 'should create the correct launch configuration' do
                expect(asg_mock).to receive(:create_launch_configuration)
                  .with(
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    image_id: "ami-abc123",
                    iam_instance_profile: 'arn:aws:iam::902170953588:' \
                      'instance-profile/test-cluster-PodbayInstanceProfile-' \
                      '1JW2ZRDFDUBN5',
                    associate_public_ip_address: "false",
                    security_groups: ["sg-01234567"],
                    instance_type: 't2.small',
                    user_data: gen_user_data(
                      registrar: 'off',
                      consul: {
                        role: 'client',
                        cluster: 'test-cluster',
                        discovery_mode: 'awstags',
                        gossip_key_file: "s3://config_bucket/gossip_key",
                        storage_location: "s3://podbay_bucket"
                      }
                    )
                  )
              end

              it 'should add tags for the modules / static_services' do
                expect(asg_mock).to receive(:create_group)
                  .with(a_hash_including(
                    tags: [
                      {
                        key: 'podbay:cluster',
                        value: 'test-cluster',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:group',
                        value: a_string_matching(/\Agr-[A-Za-z0-9]+\z/),
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:role',
                        value: 'client',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:modules:registrar',
                        value: 'off',
                        propagate_at_launch: true
                      }
                    ]
                  ))
              end
            end

            context 'with missing client security group' do
              let(:client_sg_exists) { false }

              it 'should raise an error' do
                expect { subject }.to raise_error MissingResourceError,
                  'security group for "ClientSecurityGroup" missing'
              end
            end # with missing client security group

            context 'with missing instance profile' do
              let(:instance_profile_exists) {  false }

              it 'should raise an error' do
                expect { subject }.to raise_error MissingResourceError,
                  'instance profile missing'
              end
            end # with missing instance profile

            context 'with multiple AZs' do
              after { subject }

              let(:azs) { ['us-east-1b', 'us-east-1c'] }

              it 'should create two consecutive subnets' do
                expect(cluster_mock).to receive(:create_subnets).with(
                  2, false, 24, 'podbay:group' => a_string_matching(/\Agr-.*\z/)
                )
              end

              it 'should associate the subnets to their route tables' do
                expect(private_route_tables.length).to eq 2
                expect(private_route_tables.first).to receive(:associate_with_subnet)
                  .with(
                    subnet_id: a_string_matching(/\Asubnet-[A-Za-z0-9]+\z/)
                  ).once

                expect(private_route_tables.last).to receive(:associate_with_subnet)
                  .with(
                    subnet_id: a_string_matching(/\Asubnet-[A-Za-z0-9]+\z/)
                  ).once
              end

              it 'should create a valid launch configuration' do
                expect(asg_mock).to receive(:create_launch_configuration)
                  .with(
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    image_id: "ami-abc123",
                    iam_instance_profile: "arn:aws:iam::902170953588:instance-profile/test-cluster-PodbayInstanceProfile-1JW2ZRDFDUBN5",
                    associate_public_ip_address: "false",
                    security_groups: ["sg-01234567"],
                    instance_type: 't2.small',
                    user_data: gen_user_data(
                      consul: {
                        role: 'client',
                        cluster: 'test-cluster',
                        discovery_mode: 'awstags',
                        gossip_key_file: "s3://config_bucket/gossip_key",
                        storage_location: "s3://podbay_bucket"
                      }
                    )
                  )
              end

              it 'should create a valid asg for both subnets' do
                expect(asg_mock).to receive(:create_group)
                  .with(
                    auto_scaling_group_name: a_string_matching(/\Agr-.*\z/),
                    launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                    min_size: 2,
                    max_size: 2,
                    desired_capacity: 2,
                    health_check_grace_period: "300",
                    health_check_type: "EC2",
                    vpc_zone_identifier:
                      a_string_matching(/\Asubnet-.*,subnet-.*\z/),
                    tags: [
                      {
                        key: 'podbay:cluster',
                        value: 'test-cluster',
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:group',
                        value: a_string_matching(/\Agr-[A-Za-z0-9]+\z/),
                        propagate_at_launch: true
                      },
                      {
                        key: 'podbay:role',
                        value: 'client',
                        propagate_at_launch: true
                      }
                    ]
                  )
              end
            end # with multiple AZs
          end # with servers existing

          context 'with servers not existing' do
            let(:servers_exist_resp) { false }

            it 'should raise validation error' do
              expect { subject }.to raise_error ValidationError,
                'server group must be created first before a client group can '\
                'be created'
            end
          end # with servers not existing

          context 'with role=server' do
            let(:role_val) { 'server' }

            context 'with size=5' do
              let(:size_val) { 5 }

              context 'with no servers existing' do
                let(:servers_exist_resp) { false }

                it 'should call #setup_gossip_encryption' do
                  expect(aws).to receive(:setup_gossip_encryption).once
                  subject
                end

                it 'should call #setup_backup_key' do
                  expect(aws).to receive(:setup_backup_key).once
                  subject
                end

                it 'should use PodbayServerInstanceProfile' do
                  expect(cluster_mock).to receive(:id_of)
                    .with('PodbayServerInstanceProfile')
                  subject
                end

                it 'should not use PodbayClientInstanceProfile' do
                  expect(cluster_mock).not_to receive(:id_of)
                    .with('PodbayClientInstanceProfile')
                  subject
                end

                it 'should create a valid launch configuration' do
                  expect(asg_mock).to receive(:create_launch_configuration)
                    .with(
                      launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                      image_id: "ami-abc123",
                      iam_instance_profile: "arn:aws:iam::902170953588:instance-profile/test-cluster-PodbayInstanceProfile-1JW2ZRDFDUBN5",
                      associate_public_ip_address: "false",
                      security_groups: ["sg-abcdefgh"],
                      instance_type: 't2.small',
                      user_data: gen_user_data(
                        consul: {
                          role: 'server',
                          cluster: 'test-cluster',
                          expect: 5,
                          discovery_mode: 'awstags',
                          gossip_key_file: "s3://config_bucket/gossip_key",
                          storage_location: "s3://podbay_bucket"
                        }
                      )
                    )

                  subject
                end

                it 'should create a valid Autoscaling Group' do
                  expect(asg_mock).to receive(:create_group)
                    .with(
                      auto_scaling_group_name: a_string_matching(/\Agr-.*\z/),
                      launch_configuration_name: a_string_matching(/\Agr-.*\z/),
                      min_size: 5,
                      max_size: 5,
                      desired_capacity: 5,
                      health_check_grace_period: "300",
                      health_check_type: "EC2",
                      vpc_zone_identifier: a_string_matching(/\Asubnet-.*\z/),
                      tags: [
                        {
                          key: 'podbay:cluster',
                          value: 'test-cluster',
                          propagate_at_launch: true
                        },
                        {
                          key: 'podbay:group',
                          value: a_string_matching(/\Agr-[A-Za-z0-9]+\z/),
                          propagate_at_launch: true
                        },
                        {
                          key: 'podbay:role',
                          value: 'server',
                          propagate_at_launch: true
                        }
                      ])

                  subject
                end

                context 'with missing server security group' do
                  let(:server_sg_exists) { false }

                  it 'should raise an error' do
                    expect { subject }.to raise_error MissingResourceError,
                      'security group for "ServerSecurityGroup" missing'
                  end
                end
              end # with no servers existing

              context 'with servers already existing' do
                let(:servers_exist_resp) { true }

                it 'should raise validation error' do
                  expect { subject }.to raise_error ValidationError,
                    'only one server group is allowed per cluster'
                end
              end # with servers already existing
            end # with size=5
          end # with role=server
        end # with valid params
      end # #bootstrap

      describe '#teardown' do
        subject { aws.teardown(*args, params) }

        let(:args) { [group_name] }
        let(:params) {{}}
        let(:group_name) { 'gr-abc123' }

        let(:elb_mock) { double('Resources::ELB') }
        let(:asg_mock) { double('Resources::AutoScaling') }
        let(:cluster_mock) { double('Cluster') }

        around do |ex|
          aws.mock_cluster(cluster_mock) do
            Aws::Resources::ELB.mock(elb_mock) do
              Aws::Resources::AutoScaling.mock(asg_mock) do
                ex.run
              end
            end
          end
        end

        before do
          allow(asg).to receive(:exists?).and_return(asg_exists)

          allow(asg_mock).to receive(:teardown_group).with(asg)

          allow(cluster_mock).to receive(:subnets_of_group).and_return(subnets)
          allow(cluster_mock).to receive(:asg_of_group).and_return(asg)

          allow(aws).to receive(:sleep).with(5)
        end

        let(:asg) { double('asg') }
        let(:asg_exists) { true }
        let(:subnets) do
          subnet_ids.map do |id|
            double("subnet-#{id}", id: id, delete: true,
              network_interfaces: network_interfaces)
          end
        end
        let(:subnet_ids) { ['subnet-abc1234', 'subnet-1234abc'] }
        let(:launch_config_exists) { true }
        let(:network_interfaces) { [] }

        it 'should delete the subnets' do
          subnets.each { |s| expect(s).to receive(:delete) }
          subject
        end

        context 'with no launch configuration' do
          let(:launch_config_exists) { false }
          it 'should not try to lookup the launch config for deletion' do
            expect(asg_mock).not_to receive(:launch_configuration)
            subject
          end
        end

        context 'with missing asg' do
          let(:asg_exists) { false }

          it 'should not attempt to teardown the asg' do
            expect(asg_mock).not_to receive(:teardown_group)
            subject
          end
        end # with missing asg

        context 'with network interfaces not detached' do
          let(:network_interfaces) do
            [
              double('network-interface', id: 'eni-abc1234'),
              double('network-interface', id: 'eni-1234abc')
            ]
          end

          it 'should raise an error' do
            expect { subject }.to raise_error RuntimeError, "Subnet has " \
              "network interfaces still in use: eni-abc1234, eni-1234abc"
          end
        end
      end # #teardown

      describe '#deploy', :deploy do
        subject { aws.deploy(params) }

        let(:params) do
          {}.tap do |h|
            h.merge!(ami: ami_val) if ami_val
            h.merge!(group: group_val) if group_val
            h.merge!(instance_type: instance_type_val) if instance_type_val
          end
        end
        let(:ami_val) { 'ami-abc123' }
        let(:group_val) { 'gr-01234567' }
        let(:instance_type_val) { nil }

        let(:consul_mock) { double('consul') }
        let(:cluster_mock) { double('Cluster') }
        let(:asg_mock) { double('Resources::AutoScaling') }

        around do |ex|
          Podbay::Consul.mock(consul_mock) do
            Aws::Resources::AutoScaling.mock(asg_mock) do
              aws.mock_cluster(cluster_mock) do
                ex.run
              end
            end
          end
        end

        before do
          allow(consul_mock).to receive(:ready?).and_return(consul_ready)
          allow(cluster_mock).to receive(:asg_of_group).and_return(old_asg)
          allow(asg_mock).to receive(:role_of).with(old_asg).and_return(role)

          allow(old_asg).to receive(:launch_configuration).and_return(
            old_launch_config
          )

          allow(old_asg).to receive(:desired_capacity).and_return(num_instances)
          allow(asg_mock).to receive(:copy_launch_config)
            .and_return(new_launch_config)
          allow(asg_mock).to receive(:copy_group).and_return(new_asg)
          allow(asg_mock).to receive(:step_deploy)
        end

        let(:new_asg) { double('New Asg') }
        let(:new_launch_config) { double('New Launch Configuration') }
        let(:old_asg) { double('Old Asg') }
        let(:old_launch_config) do
          double('Old Launch Configuration', image_id: old_ami)
        end
        let(:old_ami) { 'ami-123456' }
        let(:consul_ready) { true }
        let(:role) { 'client' }
        let(:num_instances) { 2 }

        context 'without consul ready' do
          let(:consul_ready) { false }

          it 'should raise an error' do
            expect { subject }.to raise_error(
              'Deploy running on node with no consul agent')
          end
        end

        context 'with old asg not found' do
          before do
            allow(cluster_mock).to receive(:asg_of_group).and_return(nil)
          end

          it 'should raise an error' do
            expect { subject }.to raise_error MissingResourceError,
              'AutoScalingGroup not found'
          end
        end

        it 'should copy the launch configuration' do
          expect(asg_mock).to receive(:copy_launch_config)
            .with(old_launch_config,
              image_id: ami_val,
              launch_configuration_name: a_string_matching(/\Agr-.*[0-9]{14}\z/)
            )

          subject
        end

        it 'should copy the autoscaling group' do
          expect(asg_mock).to receive(:copy_group).with(old_asg,
            auto_scaling_group_name: a_string_matching(/\Agr-.*[0-9]{14}\z/),
            launch_configuration_name: a_string_matching(/\Agr-.*[0-9]{14}\z/),
            min_size: 0,
            max_size: 0,
            desired_capacity: 0
          )

          subject
        end

        it 'should call #step_deploy' do
          expect(asg_mock).to receive(:step_deploy)
            .with(new_asg, old_asg, num_instances)

          subject
        end

        context 'with no ami passed in' do
          let(:ami_val) { nil }

          it "should use the old launch config's ami" do
            expect(asg_mock).to receive(:copy_launch_config)
              .with(old_launch_config, a_hash_including(image_id: old_ami))
            subject
          end
        end # with no ami passed in

        context 'with changing instance type' do
          let(:instance_type_val) { 'm3.medium' }

          context 'with server deployment' do
            let(:role) { 'server' }

            it 'should raise an error' do
              expect { subject }.to raise_error 'changing server ' \
                'configuration is not supported'
            end
          end

          context 'with client deployment' do
            let(:role) { 'client' }

            it 'should change the instance type' do
              expect(asg_mock).to receive(:copy_launch_config)
                .with(old_launch_config,
                  a_hash_including(instance_type: 'm3.medium')
                )

              subject
            end
          end
        end # with changing instance type
      end # #deploy

      describe '#upgrade', :upgrade do
        subject { aws.upgrade(params) }

        let(:params) { { ami: ami_val } }
        let(:ami_val) { 'ami-abc123' }
        let(:cluster_mock) { double('Cluster') }
        let(:asg_mock) { double('ASG') }
        let(:ec2_utils_mock) { double('EC2 Utils mock') }

        around do |ex|
          aws.mock_cluster(cluster_mock) do
            Utils::EC2.mock(ec2_utils_mock) do
              Aws::Resources::AutoScaling.mock(asg_mock) do
                ex.run
              end
            end
          end
        end

        before do
          allow(cluster_mock).to receive(:groups).and_return(groups)
          allow(ec2_utils_mock).to receive(:instance_id)
            .and_return(instance_id)

          allow(asg_mock).to receive(:group_of_instance).with(instance_id)
            .and_return(group_of_this_instance)
        end

        let(:groups) do
          group_details.map do |name, ami|
            double('group', name: name,
              launch_configuration: double(image_id: ami))
          end
        end
        let(:instance_id) { 'i-abc12345' }
        let(:group_of_this_instance) { 'gr-edcabca2d7f58fd9-20160822120600' }

        context 'with no groups in cluster' do
          let(:group_details) { {} }

          it 'should return a message' do
            is_expected.to eq "No groups found for cluster #{cluster.inspect}"
          end

          it 'should not call deploy' do
            expect(aws).not_to receive(:deploy)
            subject
          end
        end # with no groups in cluster

        context 'with groups in cluster' do
          after do
            begin
              subject
            rescue Interrupt
              nil
            end
          end

          let(:group_details) do
            {
              'gr-edc4fba2d7f58fd9-20160822120600' => 'ami-123456',
              'gr-abc4fba2d7f58fd9-20160822120600' => 'ami-123456'
            }
          end

          it 'should call deploy for each group' do
            expect(aws).to receive(:deploy)
              .with(group: 'gr-edc4fba2d7f58fd9', ami: ami_val)

            expect(aws).to receive(:deploy)
              .with(group: 'gr-abc4fba2d7f58fd9', ami: ami_val)
          end

          context 'with current group in cluster' do
            let(:group_details) do
              {
                group_of_this_instance => 'ami-123456',
                'gr-abc4fba2d7f58fd9-20160822120600' => 'ami-123456'
              }
            end

            it 'should call deploy only once' do
              expect(aws).to receive(:deploy).once
            end

            it 'should not call deploy on this group' do
              expect(aws).not_to receive(:deploy)
                .with(group: group_of_this_instance, ami: ami_val)
            end

            it 'should still upgrade the other groups' do
              expect(aws).to receive(:deploy)
                .with(group: 'gr-abc4fba2d7f58fd9', ami: ami_val)
            end
          end

          context 'with an already upgraded group' do
            let(:group_details) do
              {
                'gr-edc4fba2d7f58fd9-20160822120600' => 'ami-123456',
                'gr-abc4fba2d7f58fd9-20160822120600' => ami_val
              }
            end

            it 'should not call deploy on the already upgrade group' do
              expect(aws).not_to receive(:deploy)
                .with(group: 'gr-abc4fba2d7f58fd9', ami: ami_val)
            end

            it 'should still upgrade other groups' do
              expect(aws).to receive(:deploy)
                .with(group: 'gr-edc4fba2d7f58fd9', ami: ami_val)
            end
          end

          context 'with error during group deploy' do
            it 'should continue upgrading the other groups' do
              expect(aws).to receive(:deploy)
                .with(group: 'gr-edc4fba2d7f58fd9', ami: ami_val)
                  .and_raise(MissingResourceError).ordered
              expect(aws).to receive(:deploy)
                .with(group: 'gr-abc4fba2d7f58fd9', ami: ami_val).ordered
            end
          end

          context 'with interrupt during group deploy' do
            before do
              allow(aws).to receive(:deploy)
                .with(group: 'gr-edc4fba2d7f58fd9', ami: ami_val)
                  .and_raise(Interrupt)
            end

            it 'should not continue upgrading the subsequent groups' do
              expect(aws).not_to receive(:deploy)
                .with(group: 'gr-abc4fba2d7f58fd9', ami: ami_val)
            end

            it 'should raise the interrupt error' do
              expect { subject }.to raise_error Interrupt
            end
          end
        end # with groups in cluster
      end # #upgrade

      describe '#db_setup' do
        subject { aws.db_setup(params) }

        let(:params) do
          {}.tap do |p|
            p.merge!(engine: engine_val) if engine_val
            p.merge!(allocated_storage: allocated_storage_val)
            p.merge!(instance_class: instance_class_val) if instance_class_val
            p.merge!(username: username_val) if username_val
            p.merge!(password: password_val) if password_val
            p.merge!(maintenance_window: maintenance_window_val) if maintenance_window_val
            p.merge!(backup_retention_period: backup_retention_period_val) if backup_retention_period_val
            p.merge!(multi_az: multi_az_params) if multi_az_params
            p.merge!(engine_version: engine_version_val) if engine_version_val
            p.merge!(license_model: license_model_val) if license_model_val
            p.merge!(group: group_val) if group_val
            p.merge!(backup_window: backup_window_val) if backup_window_val
          end
        end

        let(:engine_val) { 'postgres' }
        let(:engine_version_val) { '9.3.5' }
        let(:allocated_storage_val) { '10' }
        let(:license_model_val) { 'postgresql-license' }
        let(:maintenance_window_val) { 'tue:08:37-tue:09:07' }
        let(:backup_window_val) { '05:19-05:49' }
        let(:username_val) { 'username' }
        let(:password_val) { 'password' }
        let(:group_val) { "#{cluster}-gr-abc1234" }
        let(:instance_class_val) { nil }
        let(:backup_retention_period_val) { nil }
        let(:multi_az_params) { nil }

        let(:ec2_mock) { double('Resources::EC2') }
        let(:rds_mock) { double('Resources::RDS') }
        let(:cluster_mock) { double('Cluster') }

        around do |ex|
          aws.mock_cluster(cluster_mock) do
            Aws::Resources::EC2.mock(ec2_mock) do
              Aws::Resources::RDS.mock(rds_mock) do
                ex.run
              end
            end
          end
        end

        before do
          allow(cluster_mock).to receive(:vpc).and_return(vpc)
          allow(rds_mock).to receive(:db_engine_versions).and_return(
            [Struct.new(:version).new('9.3.5')]
          )

          allow(cluster_mock).to receive(:subnets_of_group).and_return(subnets)

          allow(ec2_mock).to receive(:create_security_group).with(
            group_name: a_string_matching(/\Adb-[a-zA-Z0-9]+\z/),
            description:
              a_string_matching(
                /\ASecurity Group for Database db-[a-zA-Z0-9]+\z/
              ),
            vpc_id: a_string_matching(/\Avpc-[a-zA-Z0-9]+\z/)
          ).and_return(security_group)

          allow(security_group).to receive(:authorize_ingress)
          allow(ec2_mock).to receive(:add_tags)
          allow(cluster_mock).to receive(:availability_zones).and_return(azs)
          allow(cluster_mock).to receive(:vpc_cidr).and_return(vpc.cidr)
          allow(cluster_mock).to receive(:private_route_tables)
            .and_return(private_route_tables)

          allow(cluster_mock).to receive(:create_subnets).and_return(
            azs.each_with_index.map do |az, i|
              double('Subnet',
                id: "subnet-#{SecureRandom.hex(4)}",
                availability_zone: az,
                cidr_block: "10.0.#{(i + 1) * 2 - 1}.0/28",
                delete: true
              )
            end
          )

          allow(rds_mock).to receive(:create_db_subnet_group).with(
            db_subnet_group_name: a_string_matching(/\Adb-[A-Za-z0-9]+\z/),
            db_subnet_group_description: a_string_matching(/.+/),
            subnet_ids: azs.map {a_string_matching(/\Asubnet-[A-Za-z0-9]+\z/) },
            tags: [
              {
                key: 'podbay:cluster',
                value: cluster
              },
              {
                key: 'podbay:database',
                value: a_string_matching(/\Adb-[A-Za-z0-9]+\z/)
              }
            ]
          ).and_return(db_subnet_group)

          allow(rds_mock).to receive(:create_db_instance).with(
            hash_including(
              db_name: a_string_matching(/\Adb[A-Za-z0-9]+\z/),
              tags: [
                {
                  key: 'podbay:cluster',
                  value: cluster
                },
                {
                  key: 'podbay:database',
                  value: a_string_matching(/\Adb-[A-Za-z0-9]+\z/)
                }
              ]
            )
          ).and_return(db)
        end

        let(:vpc) { double('VPC', id: 'vpc-abc123', cidr: '10.0.0.0/16') }
        let(:subnet_cidrs) { ['10.0.1.0/24', '10.0.3.0/24'] }
        let(:subnets) do
          subnet_cidrs.each_with_index.map do |cidr, i|
            double("subnet-abc12#{i}", id: "subnet-abc12#{i}", tags: [],
              cidr_block: cidr)
          end
        end
        let(:security_group) { double('Security Group', id: 'sg-01234567') }
        let(:azs) { ['us-east-1b', 'us-east-1c'] }
        let(:private_route_tables) do
          azs.map do |az|
            double('rt-abc1234',
              tags: [
                Struct.new(:key, :value).new('AvailabilityZone', az)
              ],
              associate_with_subnet: true
            )
          end
        end
        let(:db) do
          double('DB',
            endpoint: double(address: 'db-1ca516a0c164c611.canb6bbks3sv' \
              '.us-east-1.rds.amazonaws.com',
              port: '5432')
            )
        end
        let(:db_subnet_group) { double('DB Subnet Group') }

        it 'should create subnets for the DB' do
          expect(cluster_mock).to receive(:create_subnets).with(
            2, false, 28, 'podbay:database' => a_string_matching(/\Adb-.*\z/)
          )

          subject
        end

        it 'should return name, subnets and endpoint' do
          expect(subject).to match(
            name: /\Adb-[A-Za-z0-9]+\z/,
            cidrs: ["10.0.1.0/28", "10.0.3.0/28"],
            endpoint_address: 'db-1ca516a0c164c611.canb6bbks3sv' \
              '.us-east-1.rds.amazonaws.com',
            endpoint_port: '5432'
          )
        end

        context 'with group subnets not found' do
          let(:subnet_cidrs) { [] }
          it 'should raise an error' do
            expect { subject }.to raise_error MissingResourceError,
              'no valid subnets for group test-cluster-gr-abc1234'
          end
        end

        context 'with group subnets found' do
          context 'with 1 subnet' do
            let(:subnet_cidrs) { ['10.0.1.0/24'] }
            it 'should create a single ingress rule' do
              expect(security_group).to receive(:authorize_ingress).with(
                ip_permissions: [{
                  ip_protocol: 'tcp',
                  from_port: 5432,
                  to_port: 5432,
                  ip_ranges: [{ cidr_ip: '10.0.1.0/24' }]
                }]
              )

              subject
            end

            it 'should tag the security group' do
              expect(ec2_mock).to receive(:add_tags).with(
                security_group.id,
                'podbay:cluster' => 'test-cluster',
                'podbay:database' => a_string_matching(/\Adb-[A-Za-z0-9]+\z/)
              )

              subject
            end
          end # with 1 subnet

          context 'with 2 subnets' do
            it 'should create a ingress rules for each one' do
              expect(security_group).to receive(:authorize_ingress).with(
                ip_permissions: [{
                  ip_protocol: 'tcp',
                  from_port: 5432,
                  to_port: 5432,
                  ip_ranges: [
                    { cidr_ip: '10.0.1.0/24' },
                    { cidr_ip: '10.0.3.0/24' }
                  ]
                }]
              )

              subject
            end
          end # with 2 subnets
        end # with group subnets found

        context 'with no instance class passed in' do
          it 'should default to "db.m3.medium"' do
            expect(rds_mock).to receive(:create_db_instance).with(
              hash_including(db_instance_class: 'db.m3.medium')
            )
            subject
          end
        end

        context 'with no backup_retention_period passed in' do
          it 'should default to 7' do
            expect(rds_mock).to receive(:create_db_instance).with(
              hash_including(backup_retention_period: 7)
            )
            subject
          end
        end

        context 'with no multi_az passed in' do
          it 'should default to true' do
            expect(rds_mock).to receive(:create_db_instance).with(
              hash_including(multi_az: true)
            )
            subject
          end
        end

        context 'with failure' do
          before do
            allow(rds_mock).to receive(:create_db_instance)
              .and_raise(StandardError)
          end

          it 'should clean up the resources created' do
            expect(security_group).to receive(:delete)
            expect(db_subnet_group).to receive(:delete)

            expect { subject }.to raise_error StandardError
          end
        end
      end # #db_setup

      describe '#cache_setup' do
        subject { aws.cache_setup(params) }

        let(:params) do
          {}.tap do |p|
            p.merge!(engine: engine_val) if engine_val
            p.merge!(engine_version: engine_version_val) if engine_version_val
            p.merge!(cache_node_type: cache_node_type_val) if cache_node_type_val
            p.merge!(snapshot_window: snapshot_window_val) if snapshot_window_val
            p.merge!(group: group_val) if group_val
            if snapshot_retention_limit_val
              p.merge!(snapshot_retention_limit: snapshot_retention_limit_val)
            end
          end
        end

        let(:engine_val) { 'redis' }
        let(:engine_version_val) { '2.8.24' }
        let(:cache_node_type_val) { 'cache.m3.medium' }
        let(:snapshot_window_val) { '9:00-10:00' }
        let(:group_val) { 'gr-abc1234' }
        let(:snapshot_retention_limit_val) { nil }

        let(:ec2_mock) { double('Resources::EC2') }
        let(:elasticache_mock) { double('Resources::ElastiCache') }
        let(:cluster_mock) { double('Cluster') }

        around do |ex|
          aws.mock_cluster(cluster_mock) do
            Aws::Resources::EC2.mock(ec2_mock) do
              Aws::Resources::ElastiCache.mock(elasticache_mock) do
                ex.run
              end
            end
          end
        end

        before do
          allow(elasticache_mock).to receive(:describe_cache_engine_versions)
            .and_return(
              Struct.new(:cache_engine_versions).new([
                Struct.new(:engine_version).new('2.8.24')
              ])
            )

          allow(cluster_mock).to receive(:vpc).and_return(vpc)
          allow(cluster_mock).to receive(:subnets_of_group).and_return(subnets)

          allow(ec2_mock).to receive(:create_security_group)
            .and_return(security_group)

          allow(cluster_mock).to receive(:create_subnets).and_return(
            azs.each_with_index.map do |az, i|
              double('Subnet',
                id: "subnet-#{SecureRandom.hex(4)}",
                availability_zone: az,
                cidr_block: "10.0.#{(i + 1) * 2 - 1}.0/28",
                delete: true
              )
            end
          )

          allow(ec2_mock).to receive(:add_tags)
          allow(security_group).to receive(:authorize_ingress)
          allow(cluster_mock).to receive(:availability_zones).and_return(azs)
          allow(cluster_mock).to receive(:subnets).and_return(subnets)
          allow(cluster_mock).to receive(:vpc_cidr).and_return(vpc.cidr)
          allow(cluster_mock).to receive(:private_route_tables)
            .and_return(private_route_tables)

          allow(elasticache_mock).to receive(:create_cache_subnet_group).with(
            cache_subnet_group_name: a_string_matching(/\Aca-[A-Za-z0-9]+\z/),
            cache_subnet_group_description: a_string_matching(/.+/),
            subnet_ids: azs.map {a_string_matching(/\Asubnet-[A-Za-z0-9]+\z/) }
          ).and_return(cache_subnet_group)
          allow(elasticache_mock).to receive(:create_replication_group).with(
            hash_including(
              replication_group_id: a_string_matching(/\Aca-[A-Za-z0-9]+\z/),
              tags: [
                {
                  key: 'podbay:cluster',
                  value: cluster
                },
                {
                  key: 'podbay:cache',
                  value: a_string_matching(/\Aca-[A-Za-z0-9]+\z/)
                }
              ]
            )
          ).and_return(cache_response)

          allow(elasticache_mock).to receive(
            :describe_replication_groups
          ).and_return(cache_response)

          allow(elasticache_mock).to receive(:delete_cache_subnet_group)
        end

        let(:vpc) { double('VPC', id: 'vpc-abc123', cidr: '10.0.0.0/16') }
        let(:subnet_cidrs) { ['10.0.1.0/24', '10.0.3.0/24'] }
        let(:subnets) do
          subnet_cidrs.each_with_index.map do |cidr, i|
            double("subnet-abc12#{i}", id: "subnet-abc12#{i}", tags: [],
              cidr_block: cidr)
          end
        end
        let(:security_group) { double('Security Group', id: 'sg-01234567') }
        let(:azs) { ['us-east-1b', 'us-east-1c'] }
        let(:private_route_tables) do
          azs.map do |az|
            double('rt-abc1234',
              tags: [
                Struct.new(:key, :value).new('AvailabilityZone', az)
              ],
              associate_with_subnet: true
            )
          end
        end
        let(:cache_subnet_group) do
          double('Subnet Group response', cache_subnet_group:
            double('Cache Subnet Group', cache_subnet_group_name: 'ca-abc1234')
          )
        end
        let(:cache_response) do
          double('Cache response', replication_group: cache)
        end

        let(:cache) do
          double('cache', node_groups: [
            double('nodegroup',
              primary_endpoint: double(address: 'ca-6568e9709222' \
                '.m2nb3s.ng.0001.use1.cache.amazonaws.com',
              port: '6397'))
            ]
          )
        end

        it 'should create subnets for the cache' do
          expect(cluster_mock).to receive(:create_subnets).with(
            2, false, 28, 'podbay:cache' => a_string_matching(/\Aca-.*\z/)
          )

          subject
        end

        it 'should return cache name, subnets and endpoint' do
          expect(subject).to match(name: /\Aca-[A-Za-z0-9]+\z/,
           cidrs: ["10.0.1.0/28", "10.0.3.0/28"],
           endpoint_address: 'ca-6568e9709222.m2nb3s.ng.0001.use1.cache.amazonaws.com',
            endpoint_port: '6397')
        end

        context 'with group subnets not found' do
          let(:subnet_cidrs) { [] }
          it 'should raise an error' do
            expect { subject }.to raise_error MissingResourceError,
              'no valid subnets for group gr-abc1234'
          end
        end

        context 'with group subnets found' do
          context 'with 1 subnet' do
            let(:subnet_cidrs) { ['10.0.1.0/24'] }
            it 'should create a single ingress rule' do
              expect(security_group).to receive(:authorize_ingress).with(
                ip_permissions: [{
                  ip_protocol: 'tcp',
                  from_port: 6379,
                  to_port: 6379,
                  ip_ranges: [{ cidr_ip: '10.0.1.0/24' }]
                }]
              )

              subject
            end

            it 'should tag the security group' do
              expect(ec2_mock).to receive(:add_tags).with(
                security_group.id,
                'podbay:cluster' => 'test-cluster',
                'podbay:cache' => a_string_matching(/\Aca-[A-Za-z0-9]+\z/)
              )

              subject
            end
          end # with 1 subnet

          context 'with 2 subnets' do
            it 'should create a ingress rules for each one' do
              expect(security_group).to receive(:authorize_ingress).with(
                ip_permissions: [{
                  ip_protocol: 'tcp',
                  from_port: 6379,
                  to_port: 6379,
                  ip_ranges: [
                    { cidr_ip: '10.0.1.0/24' },
                    { cidr_ip: '10.0.3.0/24' }
                  ]
                }]
              )

              subject
            end
          end # with 2 subnets
        end # with group subnets found

        context 'with no instance class passed in' do
          it 'should default to "db.m3.medium"' do
            expect(elasticache_mock).to receive(:create_replication_group).with(
              hash_including(cache_node_type: 'cache.m3.medium')
            )
            subject
          end
        end

        context 'with no snapshot_retention_limit passed in' do
          it 'should default to 14' do
            expect(elasticache_mock).to receive(:create_replication_group).with(
              hash_including(snapshot_retention_limit: 14)
            )
            subject
          end
        end

        context 'with failure' do
          before do
            allow(elasticache_mock).to receive(:create_replication_group)
              .and_raise(StandardError)
          end

          it 'should clean up the resources created' do
            expect(security_group).to receive(:delete)
            expect(elasticache_mock).to receive(:delete_cache_subnet_group)
              .with(cache_subnet_group_name: a_string_matching(/\Aca-.*\z/))

            expect { subject }.to raise_error StandardError
          end
        end
      end # #cache_setup
    end # Aws
  end # Components
end # Podbay
