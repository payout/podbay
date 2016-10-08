module Podbay
  class Components::Aws
    RSpec.describe Validation do
      describe '#validate_bootstrap_params' do
        subject { Validation.validate_bootstrap_params(params) }
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
        let(:role_val) { 'client' }
        let(:dmz_val) { nil }
        let(:ami_val) { 'ami-abc123' }
        let(:size_val) { nil }
        let(:instance_type_val) { nil }
        let(:key_pair_val) { nil }
        let(:discovery_mode_val) { nil }
        let(:elb_params) { nil }
        let(:modules_params) { nil }

        context 'with missing params' do
          let(:role_val) { nil }
          let(:ami_val) { nil }

          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'missing params: ami, role'
          end
        end

        context 'with invalid extra params' do
          let(:params) { { invalid_param: 1, another_one: 2 } }

          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'invalid params: invalid_param, another_one'
          end
        end

        context 'with role=server' do
          let(:role_val) { 'server' }
          let(:size_val) { 5 }

          context 'with size param not set' do
            let(:size_val) { nil }

            it 'should raise an error' do
              expect { subject }.to raise_error ValidationError,
                "param 'size' is required for role=server"
            end
          end

          context 'with dmz=true' do
            let(:dmz_val) { 'true' }

            it 'should raise an error' do
              expect { subject }.to raise_error ValidationError,
                'server cannot be deployed in the DMZ'
            end
          end
        end

        context 'with invalid modules params' do
          let(:modules_params) do
            {
              invalid_param: 'value'
            }
          end

          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'invalid params: invalid_param'
          end
        end

        context 'with static_services' do
          let(:modules_params) do
            {
              static_services: static_services
            }
          end

          context 'being an array' do
            let(:static_services) { ['test-service1', 'test-service2'] }

            it 'should not raise an error' do
              expect { subject }.not_to raise_error
            end
          end

          context 'not being an array' do
            let(:static_services) { 'test-service' }

            it 'should raise an error' do
              expect { subject }.to raise_error ValidationError,
                'modules.static_services[] must be an array'
            end
          end
        end

        context 'with modules.registrar' do
          let(:modules_params) { { registrar: on_or_off } }

          context '="on"' do
            let(:on_or_off) { 'on' }
            it { expect { subject }.not_to raise_error }
          end

          context '="off"' do
            let(:on_or_off) { 'off' }
            it { expect { subject }.not_to raise_error }
          end

          context '="invalid"' do
            let(:on_or_off) { 'invalid' }

            it 'should raise validation error' do
              expect { subject }.to raise_error ValidationError,
                'modules.registrar must be either "on" or "off"'
            end
          end
        end

        context 'with invalid role' do
          let(:role_val) { 'invalid_role' }

          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'invalid role value "invalid_role"'
          end
        end

        context 'with invalid dmz' do
          let(:dmz_val) { 'invalid_dmz' }

          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'invalid dmz value "invalid_dmz"'
          end
        end

        context 'with elb params and dmz=false' do
          let(:dmz_val) { 'false' }
          let(:elb_params) { { ssl_certificate_arn: 'ssl_certificate_arn' } }

          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'ELB currently only supported in DMZ'
          end
        end

        context 'with dmz=true and missing required ELB params' do
          let(:dmz_val) { 'true' }
          let(:elb_params) do
            {
              target: '/v1/health_check',
              interval: 10,
              timeout: 5,
              healthy_threshold: 4,
              unhealthy_threshold: 4
            }
          end

          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'missing ELB params: ssl_certificate_arn'
          end
        end
      end # #validate_bootstrap_params

      describe '#validate_teardown_params' do
        subject { Validation.validate_teardown_params(group_name, params) }
        let(:params) { {} }
        let(:group_name) { 'gr-abc123' }

        context 'with invalid group_name' do
          let(:group_name) { 'invalid_group_name' }
          it 'should raise a validation error' do
            expect { subject }.to raise_error Podbay::ValidationError,
              'invalid group name: "invalid_group_name"'
          end
        end

        context 'with any param passed in' do
          let(:params) { { invalid_param: 'value' } }
          it 'should raise a validation error' do
            expect { subject }.to raise_error Podbay::ValidationError,
              'invalid params: invalid_param'
          end
        end
      end # #validate_teardown_params

      describe '#validate_deploy_params' do
        subject { Validation.validate_deploy_params(params) }
        let(:params) do
          {}.tap do |h|
            h.merge!(ami: ami_val) if ami_val
            h.merge!(group: group_val) if group_val
          end
        end
        let(:ami_val) { nil }
        let(:group_val) { nil }

        context 'with extra params' do
          let(:params) { { extra_param: 'value' } }

          it 'should raise an error' do
            expect { subject }.to raise_error 'invalid params: extra_param'
          end
        end

        context 'with missing param' do
          it 'should raise an error' do
            expect { subject }.to raise_error 'missing params: group'
          end
        end
      end # #validate_deploy_params

      describe '#validate_upgrade_params' do
        subject { Validation.validate_upgrade_params(params) }
        let(:params) { {}.tap { |h| h.merge!(ami: ami_val) if ami_val } }
        let(:ami_val) { nil }

        context 'with extra params' do
          let(:params) { { extra_param: 'value' } }

          it 'should raise an error' do
            expect { subject }.to raise_error 'invalid params: extra_param'
          end
        end

        context 'with missing param' do
          it 'should raise an error' do
            expect { subject }.to raise_error 'missing params: ami'
          end
        end

        context 'with valid params' do
          let(:ami_val) { 'ami-12345' }

          it 'should not raise an error' do
            expect { subject }.not_to raise_error
          end
        end
      end # #validate_upgrade_params

      describe '#validate_db_setup_params' do
        subject { Validation.validate_db_setup_params(params) }

        let(:rds_mock) { double('Resources::RDS') }

        around { |ex| Resources::RDS.mock(rds_mock) { ex.run } }

        before do
          allow(rds_mock).to receive(:db_engine_versions)
            .with(engine: 'postgres').and_return(
              [
                double('db_engine_version', version: '9.3.1'),
                double('db_engine_version', version: '9.3.3'),
                double('db_engine_version', version: '9.3.5')
              ]
            )
        end

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
        let(:group_val) { "test-cluster-gr-abc1234" }
        let(:instance_class_val) { nil }
        let(:backup_retention_period_val) { nil }
        let(:multi_az_params) { nil }

        context 'with missing params' do
          let(:params) { {} }
          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'missing params: engine, allocated_storage, engine_version, ' \
              'license_model, maintenance_window, username, password, group, ' \
              'backup_window'
          end
        end

        context 'with extra params' do
          let(:params) { { extra_param: 'value' } }

          it 'should raise an error' do
            expect { subject }.to raise_error Podbay::ValidationError,
              'invalid params: extra_param'
          end
        end

        context 'with invalid engine name' do
          context 'with engine=MySQL' do
            let(:engine_val) { 'MySQL' }
            it 'should raise an error' do
              expect { subject }.to raise_error Podbay::ValidationError,
                'invalid db engine "MySQL"'
            end
          end

          context 'with engine=invalid_engine' do
            let(:engine_val) { 'invalid_engine' }
            it 'should raise an error' do
              expect { subject }.to raise_error Podbay::ValidationError,
                'invalid db engine "invalid_engine"'
            end
          end
        end

        context 'with invalid engine version' do
          let(:engine_version_val) { '1.2.3' }

          it 'should raise an error' do
            expect { subject }.to raise_error Podbay::ValidationError,
              'invalid db engine version "1.2.3"'
          end
        end
      end # #validate_db_setup_params

      describe '#validate_cache_setup_params' do
        subject { Validation.validate_cache_setup_params(params) }

        let(:elasticache_mock) { double('Resources::ElastiCache') }

        around { |ex| Resources::ElastiCache.mock(elasticache_mock) { ex.run } }

        before do
          allow(elasticache_mock).to receive(:describe_cache_engine_versions)
            .with(engine: 'redis').and_return(
              double(cache_engine_versions: [
                double('db_engine_version', engine_version: '2.8.24'),
                double('db_engine_version', engine_version: '2.8.23'),
                double('db_engine_version', engine_version: '2.8.22')
              ])
            )
        end

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
        let(:engine_version_val) { '9.3.5' }
        let(:cache_node_type_val) { 'cache.m3.medium' }
        let(:snapshot_window_val) { '9:00-10:00' }
        let(:group_val) { 'gr-abc1234' }
        let(:snapshot_retention_limit_val) { nil }

        context 'with missing params' do
          let(:params) { {} }
          it 'should raise an error' do
            expect { subject }.to raise_error ValidationError,
              'missing params: engine, engine_version, snapshot_window, group'
          end
        end

        context 'with extra params' do
          let(:params) { { extra_param: 'value' } }

          it 'should raise an error' do
            expect { subject }.to raise_error Podbay::ValidationError,
              'invalid params: extra_param'
          end
        end

        context 'with invalid engine name' do
          context 'with engine=memcached' do
            let(:engine_val) { 'memcached' }
            it 'should raise an error' do
              expect { subject }.to raise_error Podbay::ValidationError,
                'invalid cache engine "memcached"'
            end
          end

          context 'with engine=invalid_engine' do
            let(:engine_val) { 'invalid_engine' }
            it 'should raise an error' do
              expect { subject }.to raise_error Podbay::ValidationError,
                'invalid cache engine "invalid_engine"'
            end
          end
        end

        context 'with invalid engine version' do
          let(:engine_version_val) { '2.9.0' }

          it 'should raise an error' do
            expect { subject }.to raise_error Podbay::ValidationError,
              'invalid cache engine version "2.9.0"'
          end
        end
      end # #validate_cache_setup_params
    end # Validation
  end # Components::Aws
end # Podbay
