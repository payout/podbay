require 'json'
require 'logger'
require 'socket'
require 'tempfile'
require 'securerandom'
require 'open3'
require 'fileutils'
require 'uri'

module Podbay
  module Components
    class Daemon < Base
      autoload(:Iptables,       'podbay/components/daemon/iptables')
      autoload(:Discoverer,     'podbay/components/daemon/discoverer')
      autoload(:LoopDevices,    'podbay/components/daemon/loop_devices')
      autoload(:ContainerInfo,  'podbay/components/daemon/container_info')
      autoload(:Process,        'podbay/components/daemon/process')
      autoload(:Modules,        'podbay/components/daemon/modules')

      PODBAY_LOG_PATH = ENV['ENV'] == 'test' ? '/dev/stdout' :
        '/var/log/podbay.log'.freeze
      IMAGE_TARS_PATH = '/var/podbay/image_tars'.freeze
      PODBAY_IP_TEMPLATE = '192.168.100.%s'.freeze
      PODBAY_NETWORK_CIDR = "#{PODBAY_IP_TEMPLATE % 0}/24".freeze
      PODBAY_BRIDGE_NAME = 'br-podbay'.freeze
      BASE_MEM_MB = 16
      BASE_CPU_SHARES = 16

      BASE_MODULES = {
        'server' => {
          consul: nil,
          listener: nil
        }.freeze,
        'client' => {
          consul: nil,
          registrar: nil,
          service_router: nil,
          garbage_collector: nil
        }.freeze
      }.freeze

      class << self
        def logger
          @_logger ||= Logger.new(PODBAY_LOG_PATH)
        end

        def reinitialize_logger
          logger.close
          @_logger = Logger.new(PODBAY_LOG_PATH)

          $stdout.reopen(PODBAY_LOG_PATH, 'a')
        end

        def logger=(logger)
          @_logger = logger
        end
      end # Class Methods

      attr_reader :bridge_tag, :event_file

      def initialize(*args)
        super
        @event_file = Tempfile.new('podbay-events').path
      end

      def setup(role)
        @bridge_tag = setup_network
        setup_iptables(bridge_tag)
        setup_consul_server_iptables if role == 'server'
        LoopDevices.create_loop_dir
        LoopDevices.resolve_tabfile
        Podbay::Utils.create_directory_path(IMAGE_TARS_PATH)
      end

      def setup_network
        bridge = _load_bridge_info

        if bridge
          # Check if the bridge is configured properly.

          # Why, Docker, why!?
          subnet = bridge['IPAM']['Config']
            .find { |h| h.key?('Subnet') }['Subnet']

          icc_disabled =
            bridge['Options']['com.docker.network.bridge.enable_icc'] == 'false'

          if subnet == PODBAY_NETWORK_CIDR && icc_disabled
            bridge_tag = "br-#{bridge['Id'][0..11]}"
          else
            # Try to remove bridge to repair.
            unless system("docker network rm #{PODBAY_BRIDGE_NAME}")
              fail "#{PODBAY_BRIDGE_NAME} is corrupted. Cannot clean because " \
                'containers are running in it.'
            end
          end
        end

        bridge_tag ||= _create_bridge
        logger.info("Podbay Bridge: #{bridge_tag}")
        bridge_tag
      end

      def setup_iptables(bridge_tag)
        _setup_ingress_chain
        _setup_egress_chain

        # Setup INPUT chain
        input_chain = Iptables.chain('INPUT')
        input_chain.rule('-i lo -p tcp --dport 3000:3999 -j ACCEPT')
          .append_if_needed

        # Setup FORWARD chain
        forward_chain = Iptables.chain('FORWARD')
        forward_chain.rule("! -i #{bridge_tag} -o #{bridge_tag} -d " \
          "#{PODBAY_NETWORK_CIDR} -j PODBAY_INGRESS").insert_if_needed(1)
        forward_chain.rule("-i #{bridge_tag} ! -o #{bridge_tag} -s " \
          "#{PODBAY_NETWORK_CIDR} -j PODBAY_EGRESS").insert_if_needed(2)

        # Setup OUTPUT chain
        output_chain = Iptables.chain('OUTPUT')
        output_chain.rule('-o lo -p tcp --dport 3000:3999 -j ACCEPT')
          .append_if_needed
        output_chain.rule('-d 10.0.0.0/8 -j ACCEPT').append_if_needed
        output_chain.rule('-d 172.16.0.0/12 -j ACCEPT').append_if_needed
        output_chain.rule('-d 192.168.0.0/16 -j ACCEPT').append_if_needed
      end

      def execute(params = {})
        reinitialize_logger

        config = _read_config(params[:config] || '/etc/podbay.conf')
        fail 'consul config missing' unless (consul_config = config[:consul])
        role = consul_config[:role] or fail 'consul config missing role'
        setup(role)

        processes = []
        @_shutdown = false

        _handle_signals('USR1') do
          reinitialize_logger
          processes.each { |p| p && p.sig_usr1}
        end

        _handle_signals('HUP', 'INT', 'QUIT', 'TERM') do
          @_shutdown = true
          processes.each { |p| p && p.term }
        end

        modules = BASE_MODULES[role].merge(config)

        processes.concat(
          modules.flat_map do |k,v|
            Modules.execute(k, self, *(v.nil? ? nil :
              (v.is_a?(Array) ? v : [v])))
          end
        ).compact!

        monitor_processes(processes)
        logger.info("Done.")
      ensure
        FileUtils.rm(event_file) if event_file && File.file?(event_file)
      end

      def setup_consul_server_iptables
        input_chain = Iptables.chain('INPUT')
        input_chain
          .rule("-p tcp --dport #{Podbay::SERVER_INFO_PORT} -j ACCEPT")
          .append_if_needed
      end

      def monitor_processes(processes)
        begin
          loop do
            # Wait for any child process to exit.
            pid = ::Process.wait
            break if @_shutdown
            process = processes.select { |p| p && p.pid == pid }.first
            process && process.respawn
          end

          logger.info("Shutting down...")

          ::Process.waitall
        rescue Errno::ECHILD
        end
      end

      def launch(service_name)
        out, status = _launch(service_name)

        if (cid = out.strip) && cid =~ /\A\h+\z/
          ContainerInfo.write_service_name(cid, service_name)
        else
          logger.error('Received unexpected output when launching ' \
            "#{service_name}: #{out.inspect}")
        end

        status
      end

      def service_config(service_name)
        (Podbay::Consul::Kv.get("services/#{service_name}") || {}).tap do |c|
          c.stringify_keys!
          c['size'] ||= '0'
          c['tmp_space'] ||= '4'
          (c['image'] ||= {}).stringify_keys!
          c['ingress_whitelist'] ||= ''
          c['egress_whitelist'] ||= ''
          c['environment'] = {} unless c['environment'].is_a?(Hash)

          c['size'] = '0' unless ('0'..'9').include?(c['size'])
          c['ingress_whitelist'] = _parse_cidr_whitelist(c['ingress_whitelist'])
          c['egress_whitelist'] = _parse_cidr_whitelist(c['egress_whitelist'])
          c['environment'] = Hash[
            c['environment'].map do |k,v|
              [k.to_s.upcase, v]
            end
          ]
        end
      end

      def logger
        self.class.logger
      end

      def reinitialize_logger
        self.class.reinitialize_logger
      end

      private

      def _launch(service_name)
        config = service_config(service_name)
        _initialize_docker_image(config)
        ip_address = _pick_ip
        external_port = _pick_port

        _setup_container_ingress(ip_address, config['ingress_whitelist'])
        _setup_container_egress(ip_address, config['egress_whitelist'])

        environment = config['environment']
        environment['PORT'] ||= '3000'
        image = "#{config['image']['name']}:#{config['image']['tag']}"
        env_opts = environment.keys.sort.map { |k| "-e #{k}" }.join(' ')

        memory = BASE_MEM_MB * 2 ** config['size'].to_i
        tmp_space_b = config['tmp_space'].to_i * 2**20
        cpu_shares = BASE_CPU_SHARES * 2 ** config['size'].to_i

        tmp_mount_path = LoopDevices.create(tmp_space_b, '4000')

        Utils.system(
          environment,
          "docker run -d --net #{PODBAY_BRIDGE_NAME} --ip #{ip_address} " \
            "-p #{external_port}:#{environment['PORT']}" \
            "#{env_opts.empty? ? '' : " #{env_opts}"} -v /dev/log:/dev/log " \
            "-v /etc/podbay/hosts:/etc/hosts:ro --read-only " \
            "-v #{tmp_mount_path}:/tmp -v #{tmp_mount_path}:/app/tmp "\
            "--tmpfs /run:size=128k --log-driver=syslog " \
            "--log-opt tag=\"#{service_name}\" " \
            "--memory-swappiness=\"0\" --memory=\"#{memory}m\" " \
            "--cpu-shares=\"#{cpu_shares}\" --restart=\"unless-stopped\" " \
            "#{image}",
          unsetenv_others: true
        ).tap { |_, success| _cleanup_docker_image(config) if success }
      end

      def _initialize_docker_image(service_cfg)
        image = service_cfg['image'].dup.freeze

        if image['src']
          _pull_via_src(image)
        else
          _pull_via_docker_repo(image)
        end
      end

      def _cleanup_docker_image(service_cfg)
        # Only need to cleanup after image tars pulled from S3.
        if service_cfg['image']['src']
          Utils.rm(_image_file_path(service_cfg['image']))
        end
      end

      def _pull_via_src(image = {})
        image_uri = URI("#{image['src']}/#{image['name']}/#{image['tag']}")

        pull_meth = "_pull_tar_from_#{image_uri.scheme}"
        if respond_to?(pull_meth, true)
          image_tar = send(pull_meth, image_uri, image)
        else
          fail Podbay::ImageRetrieveError, "unsupport scheme: #{image_uri.scheme}"
        end

        if image['sha256'].nil? ||
            Podbay::Utils.valid_sha256?(image_tar, image['sha256'])
          if Docker.load(image_tar)
            logger.info("Pulled from #{image['src']}")
          else
            fail Podbay::ImageRetrieveError, "Failed to load #{image_tar}"
          end
        else
          fail Podbay::ImageRetrieveError, "Invalid sha256 for" \
            " #{image_uri}: expected #{image['sha256']}"
        end
      end

      def _pull_tar_from_s3(image_uri, image = {})
        bucket_name = image_uri.host
        object_path = image_uri.path.gsub(/\A\//, '')

        unless Podbay::Utils::S3.object_exists?(bucket_name, object_path)
          fail Podbay::ImageRetrieveError, "Object #{object_path} " \
            "does not exist in #{bucket_name} bucket"
        end

        image_tar = _image_file_path(image)
        image_dir = File.dirname(image_tar).freeze
        Podbay::Utils.create_directory_path(image_dir)
        s3_content = Podbay::Utils::S3File.read(image_uri.to_s)

        logger.info("Downloading image via #{image_uri}...")
        File.open(image_tar, 'w') do |file_writer|
          file_writer.write(s3_content)
        end

        begin
          Podbay::Utils.gunzip_file(image_tar)
        rescue Zlib::GzipFile::Error => e
          unless e.message == 'not in gzip format'
            fail '#{image_tar} image source is corrupt'
          end
        end

        image_tar
      end

      def _image_file_path(image)
        "#{IMAGE_TARS_PATH}/#{image['name']}/#{image['tag']}".freeze
      end

      def _pull_via_docker_repo(image = {})
        unless Docker.pull(image['name'], image['tag'])
          fail Podbay::ImageRetrieveError, "Docker pull error for" \
            " #{image['name']}:#{image['tag']}"
        end
        logger.info('Pulled via docker repo')
      end

      def _read_config(config_file)
        config_file = File.expand_path(config_file)
        fail "File not found: #{config_file}" unless File.file?(config_file)
        JSON.parse(open(config_file).read, symbolize_names: true)
      end

      def _handle_signals(*signals, &block)
        signals.each { |sig| Signal.trap(sig, &block) }
      end

      def _setup_container_ingress(ip_address, whitelist = [])
        ingress_chain_name = "IP_#{ip_address}_INGRESS".freeze

        ingress_chain = Iptables.chain(ingress_chain_name)
        ingress_chain.create_or_flush

        whitelist.each do |cidr|
          fail "invalid cidr #{cidr}" unless _valid_cidr?(cidr)
          ingress_chain.rule("-s #{cidr} -j RETURN").append
        end

        ingress_chain.rule('-j DROP').append

        Iptables.chain('PODBAY_INGRESS')
          .rule("-d #{ip_address} -g #{ingress_chain_name}").insert_if_needed(2)
      end

      def _setup_container_egress(ip_address, whitelist = [])
        egress_chain_name = "IP_#{ip_address}_EGRESS".freeze

        ingress_chain = Iptables.chain(egress_chain_name)
        ingress_chain.create_or_flush

        whitelist.each do |cidr|
          fail "invalid cidr #{cidr}" unless _valid_cidr?(cidr)
          ingress_chain.rule("-d #{cidr} -j ACCEPT").append
        end

        Iptables.chain('PODBAY_EGRESS')
          .rule("-s #{ip_address} -j #{egress_chain_name}").insert_if_needed(2)
      end

      def _pick_ip
        bridge = _load_bridge_info

        unavailable_octets = bridge['Containers'].values
          .map { |v| v['IPv4Address'].scan(/[^\.\/]+/)[-2].to_i }

        available_octet = ((2..254).to_a - unavailable_octets).first
        fail 'sorry bro, no available IPs' unless available_octet
        PODBAY_IP_TEMPLATE % available_octet
      end

      def _pick_port
        port_command = "netstat -vatn | tr -s ' ' | cut -d ' ' -f 4 | " \
          "tail -n +3 | tr -s ':' | cut -d ':' -f 2 | sort | uniq"

        ports = `#{port_command}`.split("\n").map(&:to_i)
        ((3001..3999).to_a - ports).first
      end

      def _load_bridge_info
        info = `docker network inspect #{PODBAY_BRIDGE_NAME} 2> /dev/null`
        info.strip == 'null' ? nil : JSON.parse(info).last
      end

      def _valid_cidr?(cidr)
        !!Regex::CIDR_VALIDATOR.match(cidr)
      end

      def _parse_cidr_whitelist(whitelist)
        if whitelist =~ Regex::CIDR_LIST_VALIDATOR
          whitelist.split(',')
        else
          []
        end
      end

      def _create_bridge
        logger.info("Creating podbay bridge")

        network_create = 'docker network create -o ' \
          '"com.docker.network.bridge.enable_icc"="false" '\
          "--subnet=#{PODBAY_NETWORK_CIDR} #{PODBAY_BRIDGE_NAME}"

        bridge_hash = `#{network_create}`

        if bridge_hash.is_a?(String) && !bridge_hash.empty?
          "br-#{bridge_hash[0..11]}"
        else
          fail 'could not create network'
        end
      end

      def _setup_ingress_chain
        ingress_chain = Iptables.chain('PODBAY_INGRESS')
        ingress_chain.create_if_needed

        ingress_chain.rule('-m state --state RELATED,ESTABLISHED -j ACCEPT')
          .insert_if_needed
        ingress_chain.rule('-j DROP').append_if_needed
      end

      def _setup_egress_chain
        egress_chain = Iptables.chain('PODBAY_EGRESS')
        egress_chain.create_if_needed

        egress_chain.rule('-m state --state RELATED,ESTABLISHED -j ACCEPT')
          .insert_if_needed
        egress_chain.rule('-d 10.0.0.0/8 -j DROP').append_if_needed
        egress_chain.rule('-d 172.16.0.0/12 -j DROP').append_if_needed
        egress_chain.rule('-d 192.168.0.0/16 -j DROP').append_if_needed
      end
    end # Daemon
  end # Components
end # Podbay
