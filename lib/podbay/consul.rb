require 'diplomat'
require 'faraday'
require 'uri'

module Podbay
  class Consul
    include Mixins::Mockable
    mockable :service, :status, :health, :conn

    autoload(:ActionChannel, 'podbay/consul/action_channel')
    autoload(:Action,        'podbay/consul/action')
    autoload(:Service,       'podbay/consul/service')
    autoload(:Kv,            'podbay/consul/kv')
    autoload(:Lock,          'podbay/consul/lock')
    autoload(:Connection,    'podbay/consul/connection')

    GOSSIP_KEY_ROTATION_EVENT_NAME = 'gossip_key_rotation'.freeze
    RESTORE_KV_EVENT_NAME = 'restore_kv'.freeze

    attr_reader :connection

    def initialize
      @connection = Connection.new
    end

    ##
    # Wait for all health checks on the host to become healthy.
    #
    # services - services to perform health checks on (if health checks are
    #            defined)
    def node_healthy?(hostname, services = [], iterations = 60)
      print "Waiting for #{hostname} to become healthy"
      services = services.reject { |s| get_service_check(s).empty? }.freeze

      iterations.times do
        print '.'

        checks = hostname_health_checks(hostname)

        has_services = (services - checks.map { |c| c['ServiceName'] }).empty?
        passing_checks = checks.all? { |c| c['Status'] == 'passing' }

        if !checks.empty? && has_services && passing_checks
          unless services.empty?
            print " Services: #{services.join(', ').inspect} Healthy and".green
          end

          puts ' Node Healthy!'.green
          return true
        end

        sleep(6)
      end

      false
    end

    def hostname_health_checks(hostname, retries = 5)
      begin
        _health.node(hostname)
      rescue Diplomat::PathNotFound
        if (retries -= 1) >= 0
          sleep 1
          retry
        end
        raise
      end
    end

    def health_checks
      _health.state('any')
    end

    def ready?
      leader != '""'
    rescue Faraday::ConnectionFailed, Faraday::ClientError
      false
    end

    def is_leader?
      leader_ip == Utils.local_ip
    end

    def leader
      _status.leader
    end

    def leader_ip
      leader.split(':').first
    end

    def service_healthy?(service, node)
      return true if get_service_check(service).empty?
      node_checks = _health.node(node)
      service_checks = node_checks.select { |c| c['ServiceName'] == service }
      !service_checks.empty? && service_checks
        .all? { |c| c['Status'] == 'passing' }
    end

    ##
    # Blocks forever waiting for updates to the list of available services.
    def available_services(index = nil)
      loop do
        begin
          resp, nindex = _service.get_all(index: index)
          return [resp.keys - ['consul'], nindex] if nindex != index
        rescue Diplomat::Timeout
          # Continue waiting
        end
      end
    end

    ##
    # Blocks forever waiting for updates to service addresses.
    def service_addresses(service, index = nil)
      loop do
        addresses, nindex = service_addresses!(service, index)
        return [addresses, nindex] if addresses && nindex
      end
    end

    ##
    # Non-blocking request for service_addresses.
    def service_addresses!(service, index = nil)
      meta = {}
      resp = _service.get(service, :all, {index: index, wait: '2s'}, meta)

      if (nindex = meta[:index]) != index
        addresses = resp.map do |address|
          {
            id: address.ServiceID,
            ip: address.ServiceAddress,
            node: address.Node,
            port: address.ServicePort
          }
        end

        [addresses, nindex]
      end
    end

    def service_nodes(service)
      addresses, _ = service_addresses!(service)
      addresses.map { |a| a[:node] }.uniq
    end

    def register_service(params)
      _service.register(params)
    end

    def local_services
      connection.get('/v1/agent/services')[:body]
    end

    def deregister_local_service(service_id)
      connection
        .get("/v1/agent/service/deregister/#{service_id}")[:status] == 200
    end

    def get_service_definition(service_name)
      Kv.get("services/#{service_name}") || {}
    end

    def get_service_check(service_name)
      check = (Kv.get("services/#{service_name}") || {})[:check] || {}
      check.slice!(:http, :tcp, :script, :interval, :ttl)
      check[:interval] << 's' if check[:interval] =~ /\A\d+\z/

      Hash[
        check.map do |k, v|
          k = [:http, :tcp, :ttl].include?(k) ? k.to_s.upcase : k.to_s.capitalize
          [k, v]
        end
      ]
    end

    def service(name)
      Service.new(name)
    end

    def create_session(name, ttl: 15)
      connection.put('/v1/session/create',
        Name: "lock #{name.inspect}",
        TTL: "#{ttl}s",
        Behavior: 'delete'
      )[:body]['ID']
    end

    def destroy_session(id)
      connection.put("/v1/session/destroy/#{id}")[:status] == 200
    end

    def renew_session(id)
      connection.put("/v1/session/renew/#{id}")[:status] == 200
    end

    def try_lock(name, sess_id)
      connection.put("/v1/kv/locks/#{name}?acquire=#{sess_id}")[:body] == 'true'
    end

    def release_lock(name, sess_id)
      connection.put("/v1/kv/locks/#{name}?release=#{sess_id}")[:body] == 'true'
    end

    def begin_action(action_name, params = {})
      open_action_channel('consul').begin_action(action_name, params)
    end

    def open_action_channel(name)
      ActionChannel.new(name)
    end

    def flag(name)
      Kv.set("flags/#{name}", 'set')
    end

    def unflag(name)
      Kv.delete(name)
    end

    def flag?(name)
      Kv.get("flags/#{name}") == 'set'
    end

    def wait_for_flag(name, ttl: 60)
      ttl.times do
        sleep 1
        yield if block_given?

        if Podbay::Consul.flag?(name)
          Podbay::Consul.unflag(name)
          return true
        end
      end

      false
    end

    def lock(name, ttl: 15)
      lock = Lock.new(name, ttl)
      lock.lock
      yield(lock)
    ensure
      lock && lock.unlock
    end

    def fire_event(name, payload = '')
      connection.put("/v1/event/fire/#{name}", payload)
    end

    def handle_events(*event_names, &block)
      event_names.flatten!
      events, index = self.events

      loop do
        seen_events = events.select { |e| event_names.include?(e['Name']) }
          .map { |e| e['ID'] }

        events, index = self.events(index: index)

        new_events = events.select { |e| event_names.include?(e['Name']) }
          .reject { |e| seen_events.include?(e['ID']) }

        new_events.each { |e| block.call(e) }
      end
    end

    ##
    # Blocks forever waiting for updates (if you specify index).
    def events(params = {})
      loop do
        begin
          return events!(params)
        rescue Podbay::TimeoutError
          # Keep waiting
        end
      end
    end

    ##
    # Non-blocking. Will raise Podbay::TimeoutError if timeout is reached.
    def events!(params = {})
      resp = connection.get('/v1/event/list', params)
      [resp[:body], resp[:index]]
    end

    def delete_key(key, recurse: false)
      connection.delete("/v1/kv/#{key}#{recurse ? '?recurse' : ''}")
    rescue Faraday::ResourceNotFound
      false
    end

    private

    def _service
      @_service ||= Diplomat::Service.new
    end

    def _status
      @_status ||= Diplomat::Status.new
    end

    def _health
      @_health ||= Diplomat::Health.new
    end
  end # Consul
end # Podbay
