require 'securerandom'

module Podbay
  module Components
    RSpec.describe Service do
      let(:service) { Service.new(options) }
      let(:options) { {} }

      describe '#define', :define do
        subject { service.define(params) }
        around { |ex| Podbay::Consul::Kv.mock(mock_kv) { ex.run } }

        before do
          allow(mock_kv).to receive(:get).and_return(prv_def)
          allow(mock_kv).to receive(:set).and_return(true)
        end

        let(:params) { {} }
        let(:mock_kv) { double('mock Consul::Kv') }
        let(:prv_def) { nil }

        def is_expected_to_set(key, defn = nil)
          unless defn
            defn = key
            key = instance_of(String)
          end

          expect(mock_kv).to receive(:set).with(key, defn).once
          subject
        end

        context 'without service option specified' do
          let(:options) { {} }
          it { expect { subject }.to raise_error '--service must be specified' }
        end

        context 'with service option specified' do
          let(:options) { { service: 'service-name' } }

          context 'with valid size' do
            let(:params) { { size: '1' } }
            it { is_expected_to_set('services/service-name', size: '1') }
          end

          context 'with valid image name' do
            let(:params) { { image: { name: 'image/name' } } }

            it 'should set image properly' do
              is_expected_to_set('services/service-name',
                image: { name: 'image/name' }
              )
            end
          end

          context 'with valid image tag' do
            let(:params) { { image: { tag: 'tag' } } }

            it 'should set image properly' do
              is_expected_to_set('services/service-name',
                image: { tag: 'tag' }
              )
            end
          end

          context 'with valid image name and tag' do
            let(:params) do
              { image: { name: 'image/name', tag: 'tag' } }
            end

            it 'should set image properly' do
              is_expected_to_set('services/service-name',
                image: { name: 'image/name', tag: 'tag' }
              )
            end
          end

          context 'with invalid image name' do
            let(:params) { { image: { name: 'image/name!' } } }

            it 'should set image properly' do
              expect { subject }.to raise_error 'invalid image name'
            end
          end

          context 'with invalid image tag' do
            let(:params) { { image: { tag: 'tag/' } } }

            it 'should set image properly' do
              expect { subject }.to raise_error 'invalid image tag'
            end
          end

          context 'with valid s3 image src' do
            let(:params) { { image: { src: 's3://bucket-name/folder-name' } } }

            it 'should set image properly' do
              is_expected_to_set('services/service-name',
                image: { src: 's3://bucket-name/folder-name' }
              )
            end
          end

          context 'with valid other image src' do
            let(:params) { { image: { src: 'http://domain/folder-name' } } }

            it 'should set image properly' do
              is_expected_to_set('services/service-name',
                image: { src: 'http://domain/folder-name' }
              )
            end
          end

          context 'with valid image src with a trailing slash' do
            let(:params) { { image: { src: 's3://bucket-name/folder-name/' } } }

            it 'should set image properly' do
              is_expected_to_set('services/service-name',
                image: { src: 's3://bucket-name/folder-name' }
              )
            end
          end

          context 'with valid image src with double slashes' do
            let(:params) { { image: { src: 's3://bucket-name//folder-name' } } }

            it 'should set image properly' do
              is_expected_to_set('services/service-name',
                image: { src: 's3://bucket-name//folder-name' }
              )
            end
          end

          context 'with valid image sha256' do
            let(:params) { { image: { sha256: '05e8e4600ae37c3d9ab08f54f65368' \
              '811c6cb12e63ff3c762651eefbd278755f' } } }

            it 'should set image properly' do
              is_expected_to_set('services/service-name',
                image: { sha256: '05e8e4600ae37c3d9ab08f54f65368' \
              '811c6cb12e63ff3c762651eefbd278755f' }
              )
            end
          end

          context 'with invalid image src with no full path' do
            let(:params) { { image: { src: 's3://' } } }

            it 'should raise a validation error' do
              expect { subject }.to raise_error 'invalid source URL'
            end
          end

          context 'with invalid image sha256 that is short' do
            let(:params) { { image: { sha256: '05e8e4600ae37c3d9ab08f54f6' } } }

            it 'should raise a validation error' do
              expect { subject }.to raise_error 'invalid sha256'
            end
          end

          context 'with invalid image sha256 that has incorrect characters' do
            let(:params) { { image: { sha256: 'Z5e8e4600ae37c3d9ab08f54f65368' \
              '811c6cb12e63ff3c762651eefbd278755f' } } }

            it 'should raise a validation error' do
              expect { subject }.to raise_error 'invalid sha256'
            end
          end

          context 'with single CIDR in ingress_whitelist' do
            let(:params) { { ingress_whitelist: '10.0.0.0/16' } }

            it 'should set ingress_whitelist properly' do
              is_expected_to_set('services/service-name',
                ingress_whitelist: '10.0.0.0/16'
              )
            end
          end

          context 'with three CIDRs in ingress_whitelist' do
            let(:params) do
              { ingress_whitelist: '10.0.0.0/16,10.1.0.0/16,10.2.0.0/24' }
            end

            it 'should set ingress_whitelist properly' do
              is_expected_to_set('services/service-name',
                ingress_whitelist: '10.0.0.0/16,10.1.0.0/16,10.2.0.0/24'
              )
            end
          end

          context 'with stray comma in ingress_whitelist' do
            let(:params) { { ingress_whitelist: '10.0.0.0/16,' } }

            it 'should raise a validation error' do
              expect { subject }.to raise_error 'invalid ingress_whitelist list'
            end
          end

          context 'with invalid CIDR IP in ingress_whitelist' do
            let(:params) { { ingress_whitelist: '10.0.0.0.1/16' } }

            it 'should raise a validation error' do
              expect { subject }.to raise_error 'invalid ingress_whitelist list'
            end
          end

          context 'with CIDR mask to large in ingress_whitelist' do
            let(:params) { { ingress_whitelist: '10.0.0.1/33' } }

            it 'should raise a validation error' do
              expect { subject }.to raise_error 'invalid ingress_whitelist list'
            end
          end

          context 'with valid egress_whitelist' do
            let(:params) { { egress_whitelist: '10.0.0.0/16' } }

            it 'should set egress_whitelist properly' do
              is_expected_to_set('services/service-name',
                egress_whitelist: '10.0.0.0/16'
              )
            end
          end

          context 'with invalid CIDR in egress_whitelist' do
            let(:params) { { egress_whitelist: '10.0.0/16' } }

            it 'should set egress_whitelist properly' do
              expect { subject }.to raise_error 'invalid egress_whitelist list'
            end
          end

          context 'with previous size' do
            let(:prv_def) { { size: '1' } }
            let(:params) { { size: '3' } }

            it 'should set new size' do
              is_expected_to_set(size: '3')
            end
          end

          context 'with previous image name' do
            let(:prv_def) { { image: { name: 'old', tag: 'tag' } } }
            let(:params) { { image: { name: 'new' } } }

            it 'should set new image name but keep tag' do
              is_expected_to_set(image: { name: 'new', tag: 'tag' })
            end
          end

          context 'with previous ingress_whitelist' do
            let(:prv_def) { { ingress_whitelist: '10.0.0.0/16' } }
            let(:params) { { ingress_whitelist: '192.168.0.0/24' } }

            it 'should set new ingress_whitelist' do
              is_expected_to_set(ingress_whitelist: '192.168.0.0/24')
            end
          end

          context 'with previous egress_whitelist' do
            let(:prv_def) { { egress_whitelist: '10.0.0.0/16' } }
            let(:params) { { egress_whitelist: '192.168.0.0/24' } }

            it 'should set new egress_whitelist' do
              is_expected_to_set(egress_whitelist: '192.168.0.0/24')
            end
          end

          context 'with valid check.interval value without "s"' do
            let(:params) { { check: { interval: '10' } } }

            it 'should set check.interval properly' do
              is_expected_to_set(check: { interval: '10s' })
            end
          end

          context 'with valid check.interval value with "s"' do
            let(:params) { { check: { interval: '10s' } } }

            it 'should set check.interval properly' do
              is_expected_to_set(check: { interval: '10s' })
            end
          end

          context 'with valid check.ttl value without "s"' do
            let(:params) { { check: { ttl: '30' } } }

            it 'should set check.ttl properly' do
              is_expected_to_set(check: { ttl: '30s' })
            end
          end

          context 'with valid check.ttl value with "s"' do
            let(:params) { { check: { ttl: '30s' } } }

            it 'should set check.ttl properly' do
              is_expected_to_set(check: { ttl: '30s' })
            end
          end

          context 'with valid check.tcp value with lowercase "true"' do
            let(:params) { { check: { tcp: 'true' } } }

            it 'should set check.tcp properly' do
              is_expected_to_set(check: { tcp: 'true' })
            end
          end

          context 'with valid check.tcp value with lowercase "false"' do
            let(:params) { { check: { tcp: 'false' } } }

            it 'should set check.tcp properly' do
              is_expected_to_set(check: { tcp: 'false' })
            end
          end

          context 'with valid check.tcp value with uppercase "true"' do
            let(:params) { { check: { tcp: 'TruE' } } }

            it 'should set check.tcp properly' do
              is_expected_to_set(check: { tcp: 'true' })
            end
          end

          context 'with valid check.tcp value with uppercase "false"' do
            let(:params) { { check: { tcp: 'FalsE' } } }

            it 'should set check.tcp properly' do
              is_expected_to_set(check: { tcp: 'false' })
            end
          end

          context 'with invalid check.tcp value' do
            let(:params) { { check: { tcp: 'maybe' } } }

            it 'should notify invalid check.tcp' do
              expect { subject }.to raise_error 'check.tcp must be' \
                ' true or false'
            end
          end

          context 'with invalid 0 check.interval value' do
            let(:params) { { check: { interval: '0' } } }

            it 'should notify invalid check.interval' do
              expect { subject }.to raise_error 'check.interval must be a' \
              ' postive value in seconds'
            end
          end

          context 'with invalid minute check.interval value' do
            let(:params) { { check: { interval: '1m' } } }

            it 'should notify invalid check.interval' do
              expect { subject }.to raise_error 'check.interval must be a' \
              ' postive value in seconds'
            end
          end

          context 'with invalid 0 check.ttl value' do
            let(:params) { { check: { ttl: '0' } } }

            it 'should notify invalid check.ttl' do
              expect { subject }.to raise_error 'check.ttl must be a' \
              ' postive value in seconds'
            end
          end

          context 'with invalid minute check.ttl value' do
            let(:params) { { check: { ttl: '1m' } } }

            it 'should notify invalid check.ttl' do
              expect { subject }.to raise_error 'check.ttl must be a' \
              ' postive value in seconds'
            end
          end
        end # with service option specified
      end # #define

      describe '#definition', :definition do
        subject { service.definition }

        around { |ex| Podbay::Consul::Kv.mock(mock_kv) { ex.run } }

        before do
          allow(mock_kv).to receive(:get).and_return(definition)
        end

        let(:mock_kv) { double('mock Consul::Kv') }
        let(:options) { { service: 'test-service' } }
        let(:definition) { {} }

        it 'should retrieve the service definition from Consul' do
          expect(mock_kv).to receive(:get).with('services/test-service')
          subject
        end

        context 'without service option specified' do
          let(:options) { {} }
          it { expect { subject }.to raise_error '--service must be specified' }
        end

        context 'with nil definition' do
          let(:definition) { nil }
          it { is_expected.to eq({}) }
        end

        context 'with environment in definition' do
          let(:definition) do
            {
              test_key: 'test_val',
              environment: { some_env: 'some_val' }
            }
          end

          it 'should replace the environment field' do
            is_expected.to eq(
              test_key: 'test_val',
              environment: 'use service:config to view environment vars'
            )
          end
        end
      end # #definition

      describe '#config', :config do
        subject { service.config(*args) }

        around { |ex| Podbay::Consul::Kv.mock(mock_kv) { ex.run } }

        before do
          allow(mock_kv).to receive(:get).and_return(environment: prv_def)
          allow(mock_kv).to receive(:set).and_return(true)
        end

        let(:args) { [] }
        let(:mock_kv) { double('mock Consul::Kv') }
        let(:prv_def) { nil }

        def is_expected_to_set(env)
          expect(mock_kv).to receive(:set)
            .with(defn_path, hash_including(environment: env)).once
          subject
        end

        context 'without service option specified' do
          let(:options) { {} }
          it { expect { subject }.to raise_error '--service must be specified' }
        end

        context 'with service option specified' do
          let(:options) { { service: service_name } }
          let(:service_name) { 'service-name' }
          let(:defn_path) { "services/#{service_name}" }

          context 'with params' do
            before { args << params }

            context 'with configs previously set' do
              let(:prv_def) { { 'some_key' => 'value', 'another_key' => 5 } }

              context 'with new config added' do
                let(:params) { { NEW_KEY: 'some_value' } }

                it 'should set the new environment variable' do
                  is_expected_to_set(
                    SOME_KEY: 'value',
                    ANOTHER_KEY: 5,
                    NEW_KEY: 'some_value'
                  )
                end
              end # with new config added

              context 'with config value replaced' do
                let(:params) { { SOME_KEY: 'new_value' } }

                it 'should update the environment variable' do
                  is_expected_to_set(
                    SOME_KEY: 'new_value',
                    ANOTHER_KEY: 5
                  )
                end
              end # with config value replaced

              context 'when providing nothing' do
                let(:params) { {} }
                let(:args) { [] }

                it { is_expected.to eq(ANOTHER_KEY: 5, SOME_KEY: 'value') }
              end # when providing nothing

              context 'when providing an existing key' do
                let(:params) { {} }
                let(:args) { ['some_key'] }

                it { is_expected.to eq(SOME_KEY: 'value') }
              end # when providing an existing key

              context 'when providing multiple existing keys' do
                let(:params) { {} }
                let(:args) { ['some_key', 'another_key'] }

                it { is_expected.to eq(ANOTHER_KEY: 5, SOME_KEY: 'value') }
              end # when providing multiple existing keys
            end # with configs previously set

            context 'without configs previously set' do
              context 'with no params provided' do
                let(:params) { {} }
                it { is_expected.to eq({}) }
              end # with no params provided

              context 'with params provided' do
                let(:params) { { NEW_KEY: 'some_value' } }

                it { is_expected_to_set(NEW_KEY: 'some_value') }
              end # with params provided
            end # without configs previously set
          end # with params
        end # with service option specified
      end # #config

      describe '#config_delete', :config_delete do
        subject { service.config_delete(*args) }

        around { |ex| Podbay::Consul::Kv.mock(mock_kv) { ex.run } }

        before do
          allow(mock_kv).to receive(:get).and_return(environment: prv_def)
          allow(mock_kv).to receive(:set).and_return(true)
        end

        let(:args) { [] }
        let(:mock_kv) { double('mock Consul::Kv') }
        let(:prv_def) { nil }

        def is_expected_to_set(env)
          expect(mock_kv).to receive(:set)
            .with(defn_path, environment: env).once
          subject
        end

        context 'without service option specified' do
          let(:options) { {} }
          it { expect { subject }.to raise_error '--service must be specified' }
        end

        context 'with service option specified' do
          let(:options) { { service: service_name } }
          let(:service_name) { 'service-name' }
          let(:defn_path) { "services/#{service_name}" }

          context 'with configs previously set' do
            let(:prv_def) { { :SOME_KEY => 'value', :ANOTHER_KEY => 5 } }

            context 'with config to delete that exists' do
              let(:args) { ['SOME_KEY'] }

              it 'should set the remaining environment variable' do
                is_expected_to_set(
                  ANOTHER_KEY: 5
                )
              end
            end # with config to delete that exists

            context 'with config to delete that does not exist' do
              let(:args) { :RANDOM_KEY }

              it 'should set the remaining environment variable' do
                is_expected_to_set(
                  SOME_KEY: 'value',
                  ANOTHER_KEY: 5
                )
              end
            end # with config to delete that exists
          end # with configs previously set
        end # with service option specified
      end # #config_delete

      describe '#restart', :restart do
        subject { service.restart }

        let(:mock_consul) { double('Podbay::Consul') }

        around do |ex|
          Podbay::Consul.mock(mock_consul) do
            ex.run
          end
        end

        let(:mock_service) { double('Podbay::Consul::Service') }
        let(:action_id) { SecureRandom.uuid }
        let(:resp_begin_action) { double('action', id: action_id) }
        let(:options) { { service: service_name } }
        let(:service_name) { 'service-name' }
        let(:service_nodes) { ['test_node'] }
        let(:action_responses) do
          base = { id: action_id, state: 'sync' }

          [
            base,
            base.merge(data: { synced_nodes: service_nodes }),
            base.merge(data: {}),
            base.merge(
              data: { restarted_nodes: service_nodes }
            )
          ]
        end

        before do
          allow(mock_consul).to receive(:service).and_return(mock_service)
          allow(mock_service).to receive(:begin_action)
            .and_return(resp_begin_action)
          allow(mock_consul).to receive(:service_nodes).with(service_name)
            .and_return(service_nodes)
          allow(mock_service).to receive(:action)
            .and_return(*action_responses)
          allow(service).to receive(:sleep) # Don't actually sleep
          allow(mock_service).to receive(:refresh_action)
            .with(action_id, instance_of(Hash))
          allow(mock_service).to receive(:end_action).with(action_id)
        end

        after { subject }

        it 'should begin restart action in sync state' do
          expect(mock_service).to receive(:begin_action)
            .with('restart', data: {state: 'sync'})
            .and_return(resp_begin_action).once
        end

        it 'should refresh the action and set the state to restart' do
          expect(mock_service).to receive(:refresh_action)
            .with(action_id, data: hash_including(state: 'restart')).once
        end

        it 'should end action' do
          expect(mock_service).to receive(:end_action).with(action_id).once
        end

        it 'should end action even if an exception is raised' do
          expect(mock_consul).to receive(:service_nodes) { fail 'test' }
          expect(mock_service).to receive(:end_action).with(action_id)
            .at_least(1).times
          expect { subject }.to raise_error 'test'
        end

        context 'with unexpected node syncing' do
          let(:action_responses) do
            base = { id: action_id, state: 'sync' }

            [
              base,
              base.merge(data: { synced_nodes: ['unexpected_hostname'] })
            ]
          end

          it 'should exit 1' do
            expect(service).to receive(:exit).with(1).once
          end
        end
      end # #restart
    end # Service
  end # Components
end # Podbay
