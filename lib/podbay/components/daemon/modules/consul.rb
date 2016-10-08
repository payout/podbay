require 'securerandom'
require 'base64'
require 'aws-sdk'
require 'active_support/all'
require 'json'

module Podbay
  module Components
    class Daemon
      class Modules
        class Consul < Base
          include Mixins::Mockable
          mockable :backup_store

          autoload(:Backups, 'podbay/components/daemon/modules/consul/backups')

          attr_reader :config

          IGNORED_KV_KEYS = ['actions', 'locks'].freeze

          def execute(params = {})
            spawn_opts = { user: 'consul', group: 'consul' }.freeze
            @config = params.dup.freeze
            agent = Process.spawn(spawn_opts) { run_consul_agent }

            if config[:role] == 'server'
              [
                agent,
                Process.spawn(spawn_opts) { handle_events },
                Process.spawn(spawn_opts) { automated_kv_backup },
                Process.spawn(spawn_opts) { monitor_kv_store }
              ]
            else
              agent
            end
          end

          def run_consul_agent
            server_ips = discover_servers
            local_ip = Utils.local_ip
            joins = server_ips.map { |ip| "-join #{ip}" }.join(' ')
            consul_config_path = '/etc/consul.conf'.freeze

            cmd = "consul agent -syslog -config-file #{consul_config_path} " \
              "-bind=#{local_ip} -retry-interval=5s #{joins}".rstrip

            if (gossip_key = load_gossip_key(config[:gossip_key_file]))
              Utils.add_to_json_file(
                'encrypt', gossip_key, consul_config_path
              )
            else
              daemon.logger.error('missing gossip encryption key')
              return
            end

            case (role = config[:role])
            when 'server'
              cmd << " -server -bootstrap-expect #{config[:expect] || 3}"
            when 'client'
              fail 'could not find servers in cluster' if server_ips.empty?
            else
              fail "invalid role: #{role}"
            end

            exec(cmd, out: '/dev/null', err: '/dev/null')
          end

          def handle_events
            key_file = config[:gossip_key_file].freeze

            event_names = [
              Podbay::Consul::GOSSIP_KEY_ROTATION_EVENT_NAME,
              'action'
            ]
            Podbay::Consul.handle_events(event_names) do |event|
              case event['Name']
              when Podbay::Consul::GOSSIP_KEY_ROTATION_EVENT_NAME
                _handle_gossip_key_rotation_event(key_file)
              when 'action'
                _handle_action(Base64.strict_decode64(event['Payload']))
              end
            end
          end

          def discover_servers
            fail 'missing cluster' unless config[:cluster]
            discovery_mode = config[:discovery_mode] || 'awstags'
            public_send("discover_via_#{discovery_mode}")
          end

          def load_gossip_key(gossip_key_file)
            if gossip_key_file
              gossip_key = Utils::SecureS3File.new(gossip_key_file).read

              if gossip_key =~ /\A([A-Za-z0-9\/+=]+)\z/
                gossip_key
              else
                daemon.logger.error('invalid gossip encryption key')
                nil
              end
            end
          end

          def monitor_kv_store
            loop do
              sleep(60 * 5) # Check every 5 minutes
              next unless Podbay::Consul.is_leader?

              keys = Podbay::Consul::Kv.get('/', keys: true)
                .reject { |key| IGNORED_KV_KEYS.any? { |k| key.include?(k) } }

              if keys.empty?
                daemon.logger.error('KV empty, requesting KV S3 restore')
                if _kv_restore
                  daemon.logger.error('KV restoration successful')
                else
                  daemon.logger.error('KV restoration failed')
                end
              end
            end
          end

          def automated_kv_backup
            loop do
              _sleep_until_next_hour
              next unless Podbay::Consul.is_leader?

              kv_snapshot = Podbay::Consul::Kv.get('/', recurse: true)
                .reject do |h|
                  IGNORED_KV_KEYS.any? { |k| h[:key].start_with?(k) }
                end

              next unless kv_snapshot
              _backup_store.backup(kv_snapshot)
              _backup_store.shift_rolling_window
            end
          end

          ##
          # Finds a consul server within the cluster based on AWS tags.
          # Assumes it's being run on an EC2 node with a role that has the
          # ec2:DescribeInstances permission.
          def discover_via_awstags
            ident_url = 'http://169.254.169.254/latest/dynamic/' \
              'instance-identity/document'.freeze

            ident = JSON.parse(`curl #{ident_url} 2> /dev/null`).freeze
            client = ::Aws::EC2::Client.new(region: ident['region'])

            f = [
              { name: 'tag:podbay:role', values: ['server'] },
              { name: 'tag:podbay:cluster', values: [config[:cluster]] },
              { name: 'instance-state-name', values: ['running'] }
            ]

            servers = client.describe_instances(filters: f).reservations
              .reject { |r| r.instances[0].instance_id == ident['instanceId'] }

            servers.map { |server| server.instances[0].network_interfaces[0]
              .private_ip_addresses[0].private_ip_address }
          end

          private

          def _handle_action(action_payload)
            channel_name, action_id = action_payload.split(':')
            action_channel = _action_channel(channel_name)

            unless (action = action_channel.current).id == action_id
              daemon.logger.warn("Ignoring abandoned action: #{action_id}")
              return
            end

            action_method = "_handle_#{action.name}_action".freeze

            unless respond_to?(action_method, true)
              daemon.logger.warn("Ignoring unknown action #{action.name}")
              return
            end

            send(action_method, action)
          end

          def _handle_gossip_key_rotation_event(key_file)
            return unless Podbay::Consul.is_leader?

            Podbay::Consul.flag(:gossip_rotate_key_begin)

            new_key = Base64.strict_encode64(SecureRandom.random_bytes(16))

            unless system("consul keyring -install=#{new_key}")
              daemon.logger.error('could not install new key')
              return
            end

            Utils::SecureS3File.write(key_file, new_key)

            unless system("consul keyring -use=#{new_key}")
              daemon.logger.error('could not use new key')
              return
            end

            old_keys = _installed_gossip_keys.reject { |k| k == new_key }

            old_keys.each do |old_key|
              unless system("consul keyring -remove=#{old_key}")
                daemon.logger.error('could remove old key')
              end
            end

            Podbay::Consul.flag(:gossip_rotate_key_end)
          end

          def _backup_location_uri
            URI(config[:storage_location] + '/server/kv_backups')
          end

          def _action_channel(channel_name)
            Podbay::Consul.open_action_channel(channel_name)
          end

          def _backup_store
            @_backup_store ||= Backups.load(_backup_location_uri)
          end

          def _installed_gossip_keys
            cmd = 'consul keyring -list | egrep -o "  [A-Za-z0-9\+]+=*" | ' \
              'tr -d ' ' | uniq'
            `#{cmd}`.split("\n")
          end

          def _sleep_until_next_hour
            sleep((DateTime.now.end_of_hour.to_i - DateTime.now.to_i) + 1)
          end

          def _handle_restore_kv_action(action)
            return unless Podbay::Consul.is_leader?

            action.lock do |_|
              begin
                restoration_time = action[:restoration_time]
                if (time_restored_to = _kv_restore(restoration_time))
                  action[:state] = 'restored'
                  action[:time_restored_to] = time_restored_to
                else
                  action[:state] = 'failed'
                end
              rescue StandardError => e
                daemon.logger.error(e.message)
                action[:state] = 'failed'
              ensure
                action.save
              end
            end
          end

          ##
          # Restores data from the most recent backup before the param 'time'
          # Returns the timestamp it restored to. If no backup is found, it
          # returns nil.
          def _kv_restore(time = Time.now.to_s)
            if (backup = _backup_store.retrieve(Time.parse(time)))
              daemon.logger.info("Restoring from #{backup[:timestamp]}")
              backup[:data].each do |h|
                Podbay::Consul::Kv.set(h[:key], h[:value])
              end

              backup[:timestamp]
            else
              daemon.logger.error("no backups found for date #{time}")
              nil
            end
          end
        end # ConsulAgent
      end # Modules
    end # Daemon
  end # Components
end # Podbay
