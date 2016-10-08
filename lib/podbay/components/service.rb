require 'uri'

module Podbay
  module Components
    class Service < Base
      def define(params = {})
        _validate_defn(params)
        _normalize_defn(params)
        prev_defn = Podbay::Consul::Kv.get("services/#{service}") || {}
        Podbay::Consul::Kv.set("services/#{service}", _merge_defns(prev_defn, params))
      end

      def definition
        Podbay::Consul.get_service_definition(service).tap do |defn|
          if defn[:environment]
            defn[:environment] = 'use service:config to view environment vars'
          end
        end
      end

      def config(*args)
        params = args.last.is_a?(Hash) ? args.pop : {}
        retrieve_keys = args.map(&:upcase).map(&:to_sym)

        defn = Podbay::Consul.get_service_definition(service)
        config = (defn[:environment] || {}).map { |k,v| [k.upcase.to_sym, v] }
          .to_h

        # Check if setting or retrieving environment variables
        if params.empty?
          if retrieve_keys.empty?
            config
          else
            config.select { |c| retrieve_keys.include?(c) }
          end
        else
          defn[:environment] = config.merge(
            params.map { |k,v| [k.upcase.to_sym, v] }.to_h
          )
          Podbay::Consul::Kv.set("services/#{service}", defn)
        end
      end

      def config_delete(*args)
        defn = Podbay::Consul.get_service_definition(service)

        defn[:environment].reject! do |k,_|
          args.map { |a| a.upcase.to_sym }.include?(k)
        end

        Podbay::Consul::Kv.set("services/#{service}", defn)
      end

      def teardown(params = {})
      end

      def deploy(docker_image_tag, params = {})
        puts docker_image_tag
      end

      def restart
        service_obj, action_id = _restart_init(service)

        nodes = Podbay::Consul.service_nodes(service).sort.freeze
        puts "Found #{nodes.count} nodes running #{service}"

        if _restart_sync(service_obj, nodes)
          _restart_monitor(service_obj, nodes)
        else
          exit 1
        end
      ensure
        service_obj && action_id && service_obj.end_action(action_id)
      end

      private

      def _normalize_defn(defn)
        if (check = defn[:check])
          if (check_interval = check[:interval])
            check_interval << 's' unless check_interval.last == 's'
          end

          if (check_ttl = check[:ttl])
            check_ttl << 's' unless check_ttl.last == 's'
          end

          if (check_tcp = check[:tcp])
            check_tcp.downcase!
          end
        end

        if (image = defn[:image])
          if (image_src = image[:src])
            image_src.gsub!(/\/\z/, '')
          end
        end
      end

      def _validate_defn(defn)
        _validate_image_def(defn)
        _validate_container_config(defn)
        _validate_whitelists(defn)
        _validate_check(defn)
      end

      def _validate_container_config(defn)
        if (size = defn[:size]) && !('0'..'9').include?(size)
          fail 'size must be between 0-9'
        end

        if (tmp_space = defn[:tmp_space])
          unless ('4'..'2048').include?(tmp_space)
            fail 'tmp_space must be between 4-2048'
          end
        end
      end

      def _validate_image_def(defn)
        if (image = defn[:image])
          if (name = image[:name])
            fail 'invalid image name' unless name =~ %r{\A[\w\-/]+\z}
          end

          if (tag = image[:tag])
            fail 'invalid image tag' unless tag =~ %r{\A[\w\-\.]+\z}
          end

          _validate_image_src(image[:src])

          if (sha256 = image[:sha256])
            fail 'invalid sha256' unless sha256 =~ %r{\A[A-Fa-f0-9]{64}\z}
          end
        end
      end

      def _validate_image_src(src)
        if src
          begin
            fail 'invalid source URL' unless (uri = URI(src)) && uri.host
          rescue URI::InvalidURIError
            fail 'invalid source URL'
          end
        end
      end

      def _validate_whitelists(defn)
        if (ingress_whitelist = defn[:ingress_whitelist])
          unless _valid_cidr_list?(ingress_whitelist)
            fail 'invalid ingress_whitelist list'
          end
        end

        if (egress_whitelist = defn[:egress_whitelist])
          unless _valid_cidr_list?(egress_whitelist)
            fail 'invalid egress_whitelist list'
          end
        end
      end

      def _validate_check(defn)
        return unless (check = defn[:check])

        if (check_interval = check[:interval])
          unless check_interval =~ /\A[1-9][0-9]*s?\z/
            fail 'check.interval must be a postive value in seconds'
          end
        end

        if (check_ttl = check[:ttl])
          unless check_ttl =~ /\A[1-9][0-9]*s?\z/
            fail 'check.ttl must be a postive value in seconds'
          end
        end

        if (check_tcp = check[:tcp])
          unless ['true','false'].include?(check_tcp.downcase)
            fail 'check.tcp must be true or false'
          end
        end
      end

      def _valid_cidr_list?(str)
        !!Regex::CIDR_LIST_VALIDATOR.match(str)
      end

      def _merge_defns(def1, def2)
        Hash[
          (def1.keys + def2.keys).uniq.map do |key|
            v1, v2 = def1[key], def2[key]

            if v1 && v2 && v1.is_a?(Hash) && v2.is_a?(Hash)
              [key, _merge_defns(v1, v2)]
            else
              [key, v2 || v1]
            end
          end
        ]
      end

      def _restart_init(service_name)
        service = Podbay::Consul.service(service_name)
        action = service.begin_action('restart', data: {state: 'sync'}) or
          fail 'another action is in progress'
        [service, action.id]
      end

      ##
      # Performs synchronization phase of the restart process.
      def _restart_sync(service, nodes)
        print 'Syncing...'

        loop do
          sleep 1
          synced_nodes = ((service.action[:data] || {})[:synced_nodes] || [])
            .sort
          unexpected_nodes = synced_nodes - (synced_nodes & nodes)

          unless unexpected_nodes.empty?
            puts 'error:'.red + ' unexpected node(s) registered ' \
              "#{unexpected_nodes.join(',')}"
            return false
          end

          break if synced_nodes == nodes
        end

        puts 'done'.green
        return true
      end

      def _restart_monitor(service, nodes)
        action = service.action
        data = action[:data]
        service.refresh_action(action[:id],
          data: data.merge(state: 'restart')
        )

        restarted_nodes = []

        loop do
          sleep 1
          data = service.action[:data]
          current_restarted_nodes = data[:restarted_nodes] || []

          (current_restarted_nodes - restarted_nodes).each do |node|
            puts "#{node} restarted".green
          end

          restarted_nodes |= current_restarted_nodes
          break if restarted_nodes.sort == nodes || data[:state] == 'abort'
        end

        if data[:state] == 'abort'
          puts 'Restart was ' + 'aborted.'.red
          puts "Remaining nodes: #{(nodes - restarted_nodes).join(', ')}"
        else
          puts 'Restart ' + 'complete.'.green
        end
      end
    end # Service
  end # Components
end # Podbay
