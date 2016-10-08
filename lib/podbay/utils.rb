require 'socket'
require 'etc'
require 'open3'
require 'net/http'
require 'uri'
require 'json'
require 'digest'
require 'zlib'
require 'fileutils'

module Podbay
  class Utils
    include Mixins::Mockable

    autoload(:EC2,          'podbay/utils/ec2')
    autoload(:S3,           'podbay/utils/s3')
    autoload(:S3File,       'podbay/utils/s3_file')
    autoload(:SecureS3File, 'podbay/utils/secure_s3_file')
    autoload(:S3,           'podbay/utils/s3')
    autoload(:EC2,          'podbay/utils/ec2')

    def parse_cli_component_and_method(cli_str)
      component, command = cli_str.split(':', 2)
      command &&= command.tr(':', '_')

      [component, command]
    end

    def add_to_json_file(key, value, path)
      contents = File.read(path)
      data = contents.empty? ? {} : JSON.parse(contents)
      data[key] = value

      File.open(path, "w") do |f|
        f.write(JSON.pretty_generate(data))
      end
    end

    def gunzip_file(file_path)
      Zlib::GzipReader.open(file_path) do |gz|
        File.open("#{file_path}.unzipped", 'w') do |file_writer|
          file_writer.write(gz.read)
        end

        File.rename("#{file_path}.unzipped", file_path)
      end
    end

    def valid_sha256?(path, sha256)
      sha256 == Digest::SHA256.file(path).hexdigest
    end

    def create_directory_path(path)
      FileUtils.mkdir_p(path)
    end

    # Removes a file.
    def rm(path)
      FileUtils.rm_f(path)
      nil
    end

    def local_ip
      UDPSocket.open do |s|
        s.do_not_reverse_lookup = true
        s.connect('8.8.8.8', 1)
        s.addr.last
      end
    end

    def hostname
      Socket.gethostname
    end

    def split_cidr(cidr)
      cidr.scan(/[^\.\/]+/).map(&:to_i)
    end

    def join_cidr(*octets, mask)
      octets.flatten!
      (4 - octets.length).times { octets << '0' }
      octets.join('.') + "/#{mask}"
    end

    def pick_available_cidr(net_cidr, unavailable_cidrs, dmz: false, mask: 24)
      fail "mask must be within (16..31)" unless (16..31).include?(mask)

      root_octet = mask / 8 # intentionally truncating
      root_index = root_octet - 1
      octet_mask = mask - (root_octet * 8)
      net_cidr = split_cidr(net_cidr)

      unavailable_cidrs = unavailable_cidrs.map { |cidr| split_cidr(cidr) }
      parity_method = dmz ? :even? : :odd?

      possible_octets = (0..2 ** octet_mask - 1)
        .map { |i| i << (8 - octet_mask) }
      inner_gaps = unavailable_cidrs.select { |cidr| cidr.last == mask }
        .select { |cidr| cidr[root_index].send(parity_method) }
        .reduce(Hash.new([])) do |h, cidr|
          h[cidr[root_index]] += [cidr[root_index + 1]]
          h
        end
        .map { |root, taken_octets| [root, possible_octets - taken_octets] }
        .find { |_, available_octets| available_octets.length >= 1 }

      base_octets = net_cidr[0..root_index - 1]
      if inner_gaps
        join_cidr(base_octets, inner_gaps.first, inner_gaps.last.first, mask)
      else
        possible_octets = (0..255).select(&parity_method)
        taken_root_octets = unavailable_cidrs.map { |cidr| cidr[root_index] }
        available_octets = possible_octets - taken_root_octets

        unless available_octets.empty?
          join_cidr(base_octets, available_octets.first, mask)
        end
      end
    end

    ##
    # Returns a hash where the keys are the values in the passed array and the
    # values are the number of times that value appears in the list.
    def count_values(*values)
      values.inject(Hash.new(0)) { |h, v| h[v] += 1; h }
    end

    ##
    # Returns the UID for the username on the host.
    def get_uid(username)
      Etc.passwd { |u| return u.uid if u.name == username }
    end

    ##
    # Returns GID for the group on the host.
    def get_gid(group_name)
      Etc.group { |g| return g.gid if g.name == group_name }
    end

    def timestamp(time = Time.now)
      time.strftime("%Y%m%d%H%M%S")
    end

    def current_time
      Time.now
    end

    def system(*args)
      out, status = Open3.capture2(*args)
      [out, status.success?]
    end

    ##
    # Makes a GET request to the Podbay servers that are listening for Podbay
    # data requests
    def podbay_info(ip_address, path, timeout = 5)
      JSON.parse(
        get_request(
          "http://#{ip_address}:#{Podbay::SERVER_INFO_PORT}/#{path}",
          timeout: timeout
        ).body,
        symbolize_names: true
      )
    end

    def get_request(url, opts = {})
      url = URI(url)
      Net::HTTP.new(url.hostname, url.port).tap { |http|
        http.open_timeout = http.read_timeout = (opts[:timeout] || 5)
      }.get(url.path)
    end

    def prompt_question(question)
      selection = nil
      loop do
        print "#{question} (y/n): "
        selection = $stdin.gets.chomp.downcase
        break if ['y', 'n'].include?(selection)
        puts 'Invalid selection'.red
      end
      selection == 'y'
    end

    def prompt_choice(question, *choices)
      selection = ''
      loop do
        puts "\n#{question}"
        choices.each_with_index { |c, i| puts "[#{i + 1}] #{c}" }
        selection = $stdin.gets.chomp
        break if (1..(choices.length)).map(&:to_s).include?(selection)
        puts 'Invalid selection'.red
      end

      choices[selection.to_i - 1]
    end
  end # Utils
end # Podbay
