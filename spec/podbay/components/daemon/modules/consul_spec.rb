require 'securerandom'
require 'base64'

module Podbay::Components
  class Daemon::Modules
    RSpec.describe Consul do
      let(:daemon) { Daemon.new }
      let(:consul) { Consul.new(daemon) }

      def expect_system(command)
        expect(consul).to receive(:system).with(command).once
      end

      describe '#execute', :execute do
        subject { consul.execute(params) }

        # Using a random value to ensure that the same data is being passed thru
        let(:params) { { unique_flag: SecureRandom.uuid } }
        let(:mock_process) { double('Daemon::Process') }
        around { |ex| Daemon::Process.mock(mock_process) { ex.run } }

        before do
          allow(mock_process).to receive(:spawn)
            .with({user: 'consul', group: 'consul'}, nil) do |&block|
            double('mock spawn', block: block)
          end
        end

        let(:consul_block) { [subject].flatten.first.block }
        let(:event_handler_block) { _, p = subject; p.block if p }

        context 'with role = server' do
          before { params.merge!(role: 'server') }
          it { is_expected.to be_a Array }
          it { is_expected.to satisfy { |a| a.length == 4 } }

          it 'should call #run_consul_agent with expected params' do
            expect(consul).to receive(:run_consul_agent).once
            consul_block.call
          end

          it 'should call #handle_events' do
            expect(consul).to receive(:handle_events)
              .once
            event_handler_block && event_handler_block.call
          end
        end # with role = server

        context 'with role = client' do
          before { params.merge!(role: 'client') }
          it { is_expected.to be_a RSpec::Mocks::Double }

          it 'should call #run_consul_agent with expected params' do
            expect(consul).to receive(:run_consul_agent).once
            consul_block.call
          end
        end # with role = client
      end # #execute

      describe '#run_consul_agent', :run_consul_agent do
        subject { consul.run_consul_agent }
        let(:params) { {} }
        let(:local_ip) { Podbay::Utils.local_ip }
        let(:server_ips) { [] }
        let(:gossip_key) { nil }
        let(:gossip_key_file) { params[:gossip_key_file] }
        let(:mock_utils) { double('Podbay::Utils') }

        around { |ex| Podbay::Utils.mock(mock_utils) { ex.run } }

        before do
          allow(consul).to receive(:config).and_return(params)
          allow(consul).to receive(:discover_servers)
            .and_return(server_ips)
          allow(consul).to receive(:load_gossip_key)
            .and_return(gossip_key)
          allow(consul).to receive(:exec)
          allow(mock_utils).to receive(:local_ip).and_return('10.0.0.4')
          allow(mock_utils).to receive(:add_to_json_file)
        end

        after { subject rescue nil }

        context 'with gossip_key defined' do
          let(:gossip_key) { Base64.strict_encode64(SecureRandom.random_bytes) }
          before { params.merge!(gossip_key_file: 's3://dummy/key/file') }

          it 'should call #load_gossip_key with gossip_key_file from params' do
            expect(consul).to receive(:load_gossip_key).with(gossip_key_file)
          end

          it 'should call Utils.add_to_json_file with encrypt_key and ' \
            'consul_config_path' do
            expect(mock_utils).to receive(:add_to_json_file)
              .with('encrypt', gossip_key, '/etc/consul.conf').once
          end

          context 'with role = server' do
            before { params.merge!(role: 'server') }

            context 'with expect undefined' do
              context 'with no other servers running' do
                let(:server_ips) { [] }

                it 'should spawn correct command' do
                  expect(consul).to receive(:exec).with(
                    "consul agent -syslog -config-file /etc/consul.conf " \
                    "-bind=#{local_ip} -retry-interval=5s " \
                    "-server -bootstrap-expect 3",
                    {out: '/dev/null', err: '/dev/null'}
                  ).once
                end
              end # with no other servers running

              context 'with two other servers running' do
                let(:server_ips) { ['10.0.0.2', '10.0.0.3'] }

                it 'should spawn correct command' do
                  expect(consul).to receive(:exec).with(
                    "consul agent -syslog -config-file /etc/consul.conf " \
                    "-bind=#{local_ip} -retry-interval=5s " \
                    "-join 10.0.0.2 -join 10.0.0.3 " \
                    "-server -bootstrap-expect 3",
                    {out: '/dev/null', err: '/dev/null'}
                  ).once
                end
              end # with two other servers running
            end # with expect undefined

            context 'with expect = 5' do
              before { params.merge!(expect: 5) }
              let(:server_ips) { [] }

              it 'should use -bootstrap-expect 5' do
                expect(consul).to receive(:exec).with(
                  a_string_including('-bootstrap-expect 5'),
                  Hash
                ).once
              end
            end # with expect = 5
          end # with role = server

          context 'with role = client' do
            before { params.merge!(role: 'client') }

            context 'with no servers running' do
              let(:server_ips) { [] }

              it 'should raise error' do
                expect { subject }.to raise_error 'could not find servers in '\
                  'cluster'
              end
            end # with no servers running

            context 'with two servers running' do
              let(:server_ips) { ['10.0.0.2', '10.0.0.3'] }

              it 'should spawn correct command' do
                expect(consul).to receive(:exec).with(
                  "consul agent -syslog -config-file /etc/consul.conf " \
                  "-bind=#{local_ip} -retry-interval=5s -join 10.0.0.2 " \
                  "-join 10.0.0.3",
                  {out: '/dev/null', err: '/dev/null'}
                ).once
              end
            end # with two servers running
          end # with role = client

          context 'with role = invalid' do
            before { params.merge!(role: 'invalid') }

            it 'should raise error' do
              expect { subject }.to raise_error 'invalid role: invalid'
            end
          end # with role = invalid
        end # with gossip_key defined

        context 'with gossip_key undefined' do
          let(:gossip_key) { nil }
          let(:dummy_logger) { double('daemon logger') }

          before do
            allow(daemon).to receive(:logger).and_return(dummy_logger)
            allow(dummy_logger).to receive(:error)
          end

          it 'should log error' do
            expect(dummy_logger).to receive(:error)
              .with('missing gossip encryption key').once
          end

          it 'should not call exec' do
            expect(consul).not_to receive(:exec)
          end
        end # with gossip_key undefined
      end # #run_consul_agent

      describe '#discover_servers', :discover_servers do
        subject { consul.discover_servers }

        let(:params) { {} }
        let(:server_ip) { '10.0.0.10' }

        before do
          allow(consul).to receive(:discover_via_awstags)
            .and_return([server_ip])
          allow(consul).to receive(:config).and_return(params)
        end

        context 'with cluster provided' do
          after { subject }
          before { params.merge!(cluster: 'cluster-name') }

          context 'with no discovery_mode set' do
            it 'should call awstags discovery method' do
              expect(consul).to receive(:discover_via_awstags).once
            end

            it 'should return server_ip returned by discovery method' do
              is_expected.to eq [server_ip]
            end
          end

          context 'with discovery_mode = awstags' do
            before { params.merge!(discovery_mode: 'awstags') }

            it 'should call awstags discovery method' do
              expect(consul).to receive(:discover_via_awstags).once
            end

            it 'should return server_ip returned by discovery method' do
              is_expected.to eq [server_ip]
            end
          end
        end # with cluster provided

        context 'with cluster not provided' do
          it 'should raise error' do
            expect { subject }.to raise_error 'missing cluster'
          end
        end
      end # #discover_servers

      describe '#discover_via_awstags' do
        it 'should have #discover_via_awstags method' do
          expect(consul).to respond_to :discover_via_awstags
        end
      end # #discover_via_awstags

      describe '#automated_kv_backup' do
        subject { consul.automated_kv_backup }

        let(:mock_kv) { double('Podbay::Consul::Kv') }
        let(:mock_consul) { double('Podbay::Consul') }
        let(:mock_utils) { double('Podbay::Utils') }
        let(:mock_backup_store) { double('Backupstore') }

        around do |ex|
          consul.mock_backup_store(mock_backup_store) do
            Podbay::Consul.mock(mock_consul) do
              Podbay::Consul::Kv.mock(mock_kv) do
                Podbay::Utils.mock(mock_utils) do
                  ex.run
                end
              end
            end
          end
        end

        before do
          allow(consul).to receive(:config).and_return(params)
          allow(consul).to receive(:loop).and_yield
          allow(consul).to receive(:sleep)

          allow(mock_consul).to receive(:is_leader?).and_return(is_leader)
          allow(mock_backup_store).to receive(:backup)
          allow(mock_backup_store).to receive(:shift_rolling_window)
          allow(mock_utils).to receive(:current_time).and_return(current_time)
        end

        let(:params) do
          {
            storage_location: 's3://bucket-name'
          }
        end
        let(:current_time) { Time.now }

        context 'with server being a follower' do
          let(:is_leader) { false }

          it 'should not perform the backup' do
            expect(mock_kv).not_to receive(:get)
            subject
          end
        end

        context 'with server being a leader' do
          let(:is_leader) { true }

          before do
            allow(mock_kv).to receive(:get).and_return(kv_snapshot)
          end

          after { subject }

          let(:kv_snapshot) do
            [
              {
                key: "services/test-service",
                value: '{"image":{"tag":"test-tag"}}'
              }
            ]
          end

          it 'should retrieve all of the KV store values' do
            expect(mock_kv).to receive(:get).with('/', recurse: true)
          end

          it 'should backup the data' do
            expect(mock_backup_store).to receive(:backup).with(kv_snapshot)
          end

          it 'should create a daily snapshot' do
            expect(mock_backup_store).to receive(:shift_rolling_window)
          end

          it 'should sleep until the next hour' do
            secs = (DateTime.now.end_of_hour.to_i - DateTime.now.to_i) + 1
            expect(consul).to receive(:sleep).with(secs)
          end

          context 'with ignored keys in KV snapshot' do
            let(:kv_snapshot) do
              [
                {
                  key: "services/test-service",
                  value: '{"image":{"tag":"test-tag"}}'
                },
                {
                  key: "actions/test-action",
                  value: '{}'
                },
                {
                  key: "locks/test-lock",
                  value: '{}'
                }
              ]
            end

            it 'should reject all action data' do
              expect(mock_backup_store).to receive(:backup).with(
                [kv_snapshot[0]]
              )
            end
          end # with ignored keys in KV snapshot

          context 'with valid key that contains an ignored key' do
            let(:kv_snapshot) do
              [
                {
                  key: "services/actions-service",
                  value: '{}'
                }
              ]
            end

            it 'should backup the data' do
              expect(mock_backup_store).to receive(:backup).with(kv_snapshot)
            end
          end
        end # with server being a leader
      end # #automated_kv_backup

      describe '#monitor_kv_store' do
        subject { consul.monitor_kv_store }

        let(:consul_mock) { double('Podbay::Consul') }
        let(:mock_backup_store) { double('Podbay::Consul::Backup') }
        let(:mock_logger) { double('mock logger', error: nil, info: nil) }
        let(:mock_kv) { double('Podbay::Consul::Kv') }

        around do |ex|
          Podbay::Consul::Kv.mock(mock_kv) do
            Podbay::Consul.mock(consul_mock) do
              consul.mock_backup_store(mock_backup_store) do
                ex.run
              end
            end
          end
        end

        before do
          allow(mock_kv).to receive(:get).and_return(keys)

          allow(consul).to receive(:loop).and_yield
          allow(consul).to receive(:sleep)
          allow(daemon).to receive(:logger).and_return(mock_logger)
          allow(consul_mock).to receive(:is_leader?).and_return(is_leader)

          allow(mock_backup_store).to receive(:retrieve)
            .and_return(retrieve_data)
          allow(mock_kv).to receive(:set)
        end

        after { subject }

        let(:is_leader) { false }
        let(:keys) { [] }
        let(:retrieve_data) do
          {
            timestamp: Time.now.to_s,
            data: [
              {
                key: "services/test",
                value: '{"image":{"tag":"test-tag"}}'
              },
              {
                key: "services/another-test",
                value: '{"image":{"tag":"another-test-tag"}}'
              }
            ]
          }
        end

        it 'should check every 5 minutes' do
          expect(consul).to receive(:sleep).with(300)
        end

        context 'with being a follower' do
          let(:is_leader) { false }

          it 'should not attempt to retreive backup data' do
            expect(mock_backup_store).not_to receive(:retrieve)
          end
        end

        context 'with being a leader' do
          let(:is_leader) { true }

          context 'with healthy kv store' do
            let(:keys) { ['services/test'] }

            it 'should not attempt to retreive backup data' do
              expect(mock_backup_store).not_to receive(:retrieve)
            end
          end # with healthy kv store

          context 'with kv store data loss' do
            let(:keys) { [] }

            it 'should log the error' do
              expect(mock_logger).to receive(:error)
                .with('KV empty, requesting KV S3 restore')
            end

            it 'should retreive backup data' do
              expect(mock_backup_store).to receive(:retrieve)
            end

            it 'should restore the kv store' do
              retrieve_data[:data].each do |h|
                expect(mock_kv).to receive(:set).with(h[:key], h[:value])
              end
            end

            context 'with no backup data' do
              let(:retrieve_data) { nil }

              it 'should log the error' do
                expect(mock_logger).to receive(:error)
                  .with("no backups found for date #{Time.now.to_s}")
              end
            end # with no backup data

            context 'with ignored kv keys' do
              let(:keys) { ['locks/test', 'actions/test'] }

              it 'should log the error' do
                expect(mock_logger).to receive(:error)
                  .with('KV empty, requesting KV S3 restore')
              end

              it 'should retreive backup data' do
                expect(mock_backup_store).to receive(:retrieve)
              end

              it 'should restore the kv store' do
                retrieve_data[:data].each do |h|
                  expect(mock_kv).to receive(:set).with(h[:key], h[:value])
                end
              end
            end # with ignored kv keys
          end # with kv store data lost
        end # with being a leader
      end # #monitor_kv_store

      describe '#handle_events', :handle_events do
        subject { consul.handle_events }

        let(:mock_consul) { double('Podbay::Consul') }
        let(:mock_kv) { double('Podbay::Consul:Kv') }
        let(:mock_backup_store) { double('Podbay::Consul::Backup') }
        let(:mock_secure_s3_file) { double('Podbay::Utils::SecureS3File') }

        around do |ex|
          Podbay::Consul::Kv.mock(mock_kv) do
            Podbay::Consul.mock(mock_consul) do
              Podbay::Utils::SecureS3File.mock(mock_secure_s3_file) do
                consul.mock_backup_store(mock_backup_store) do
                  ex.run
                end
              end
            end
          end
        end

        before do
          allow(consul).to receive(:config).and_return(params)
          allow(mock_consul).to receive(:handle_events).and_yield(event)
          allow(mock_consul).to receive(:is_leader?).and_return(is_leader)
          allow(mock_consul).to receive(:flag)
          allow(mock_consul).to receive(:open_action_channel)
            .and_return(action_channel)
          allow(consul).to receive(:system).and_return(true)
          allow(daemon).to receive(:logger).and_return(mock_logger)

          allow(mock_secure_s3_file).to receive(:new)
            .and_return(s3_file_instance)
          allow(s3_file_instance).to receive(:write)
          allow(consul).to receive(:`).and_return(gossip_keys_list)
        end

        let(:params) { { gossip_key_file: gossip_key_file } }
        let(:mock_logger) { double('Logger', warn: nil, error: nil, info: nil) }
        let(:gossip_key_file) { 's3://bucket/path/file' }
        let(:s3_file_instance) { double('SecureS3File instance') }
        let(:action_channel) { double('action channel') }
        let(:old_key) { "PPbkIO4NOLLzTkJc5DOjlw==" }
        let(:gossip_keys_list) { old_key.dup }
        let(:is_leader) { true }
        let(:event) { {} }

        after { subject }

        context 'with event=GOSSIP_KEY_ROTATION_EVENT_NAME' do
          let(:event) do
            {
              'Name' => Podbay::Consul::GOSSIP_KEY_ROTATION_EVENT_NAME
            }
          end

          context 'with non-leader server receiving event' do
            let(:is_leader) { false }

            it 'should not set gossip_rotate_key_begin flag' do
              expect(mock_consul).not_to receive(:flag)
                .with(:gossip_rotate_key_begin)
            end
          end

          context 'with leader server receiving event' do
            let(:is_leader) { true }

            it 'should use passed gossip_key_file' do
              expect(mock_secure_s3_file).to receive(:new).with(gossip_key_file)
                .once
            end

            it 'should install new key properly' do
              expect(mock_consul).to receive(:flag).ordered.once
                .with(:gossip_rotate_key_begin)

              expect(consul).to receive(:system).once.with(
                a_string_starting_with('consul keyring -install=')
              ) do |cmd|
                new_key = cmd[24..-1]

                expect(s3_file_instance).to receive(:write).with(new_key).ordered
                  .once

                expect(consul).to receive(:system).ordered.once
                  .with("consul keyring -use=#{new_key}")

                gossip_keys_list << "\n#{new_key}"

                expect(consul).to receive(:system).ordered.once
                  .with("consul keyring -remove=#{old_key}")

                expect(consul).not_to receive(:system)
                  .with("consul keyring -remove=#{new_key}")

                expect(mock_consul).to receive(:flag).ordered.once
                  .with(:gossip_rotate_key_end)

                true
              end
            end # with event=GOSSIP_KEY_ROTATION_EVENT_NAME
          end
        end # with event=GOSSIP_KEY_ROTATION_EVENT_NAME

        context 'with event=action' do
          before do
            allow(action_channel).to receive(:current)
              .and_return(current_action)

            allow(current_action).to receive(:lock).and_yield(double('lock'))
            allow(current_action).to receive(:[]=)
            allow(current_action).to receive(:[]) do |k|
              current_action_data[k]
            end
          end

          let(:current_action_data) do
            {
              restoration_time: Time.now.to_s
            }
          end
          let(:current_action) do
            double('current_action',
              id: current_action_id,
              name: current_action_name
            )
          end
          let(:current_action_name) { '' }
          let(:current_action_id) { action_id }
          let(:action_id) { SecureRandom.uuid }
          let(:event) do
            {
              'Name' => 'action',
              'Payload' => Base64.strict_encode64("consul:#{action_id}")
            }
          end

          after { subject }

          context 'with action id not matching current id' do
            let(:current_action_id) { SecureRandom.uuid }

            it 'should log a warning' do
              expect(mock_logger).to receive(:warn).with(
                "Ignoring abandoned action: #{action_id}"
              )
            end

            it 'should not handle the event' do
              expect(consul).not_to receive(:send)
            end

            it { is_expected.to be nil }
          end

          context 'with unknown action_name' do
            let(:current_action_name) { 'restore_kv_action' }

            it 'should log a warning' do
              expect(mock_logger).to receive(:warn).with(
                "Ignoring unknown action #{current_action_name}"
              )
            end

            it 'should not handle the event' do
              expect(consul).not_to receive(:send)
            end
          end # with unknown action_name

          context 'with action name=restore_kv_action' do
            let(:current_action_name) { 'restore_kv' }

            context 'with not being leader' do
              let(:is_leader) { false }

              it 'should not retrieve the data' do
                expect(mock_backup_store).not_to receive(:retrieve)
              end
            end # with not being leader

            context 'with being leader' do
              let(:is_leader) { true }
              let(:retrieve_data) do
                {
                  timestamp: current_action_data[:restoration_time],
                  data: [
                    {
                      key: "services/test",
                      value: '{"image":{"tag":"test-tag"}}'
                    },
                    {
                      key: "services/another-test",
                      value: '{"image":{"tag":"another-test-tag"}}'
                    }
                  ]
                }
              end

              before do
                allow(mock_backup_store).to receive(:retrieve)
                  .and_return(retrieve_data)
                allow(mock_kv).to receive(:set)

                allow(current_action).to receive(:save)
              end

              it 'should retrieve the most recent kv backup data' do
                expect(mock_backup_store).to receive(:retrieve).with(
                  Time.parse(current_action_data[:restoration_time])
                )
              end

              it 'should restore the kv store' do
                retrieve_data[:data].each do |h|
                  expect(mock_kv).to receive(:set).with(h[:key], h[:value])
                end
              end

              it 'should save the action' do
                expect(current_action).to receive(:save)
              end

              it 'should set the action state to restored' do
                expect(current_action).to receive(:[]=).with(:state, 'restored')
              end

              it 'should set the action time_restored_to to the timestamp' do
                expect(current_action).to receive(:[]=).with(:time_restored_to,
                  retrieve_data[:timestamp])
              end

              it 'should log the timestamp it is restoring to' do
                expect(mock_logger).to receive(:info).with(
                  "Restoring from #{retrieve_data[:timestamp]}"
                )
              end

              context 'with no backup data' do
                let(:retrieve_data) { nil }

                it 'should log the error' do
                  expect(mock_logger).to receive(:error).with(
                    "no backups found for date #{current_action_data[:restoration_time]}"
                  )
                end

                it 'should save the action' do
                  expect(current_action).to receive(:save)
                end

                it 'should set the action state to failed' do
                  expect(current_action).to receive(:[]=).with(:state, 'failed')
                end
              end

              context 'with exception' do
                before do
                  allow(mock_kv).to receive(:set).and_raise(StandardError)
                end

                it 'should log the error' do
                  expect(mock_logger).to receive(:error).with('StandardError')
                end

                it 'should save the action' do
                  expect(current_action).to receive(:save)
                end

                it 'should set the action state to failed' do
                  expect(current_action).to receive(:[]=).with(:state, 'failed')
                end
              end # with exception
            end # with being leader
          end # with action name=restore_kv_action
        end # end # with event=action
      end # handle_events
    end # Consul
  end # Daemon::Modules
end # Podbay::Components
