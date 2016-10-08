require 'optparse'
require 'json'

module Podbay
  module CLI
    class Arguments
      attr_reader :args
      attr_reader :options
      attr_reader :component

      def initialize(cli_args)
        @options = {}
        @args = []
        _parse(cli_args)
      end

      def command
        @cmd || 'execute'
      end

      def component
        @component || 'help'
      end

      private

      def _parse(cli_args)
        options = _parse_options(cli_args).freeze
        return unless cli_args[0]

        @component, @cmd = Utils.parse_cli_component_and_method(cli_args[0])
        @args = cli_args[1..-1].select { |a| !a.include?('=') }
        params = _parse_params(cli_args[1..-1].select { |a| a.include?('=') })

        if options[:params_file]
          params = _merge_file_params(options[:params_file], params)
        end
        @args.push(params) unless params.empty?
      end

      def _parse_options(cli_args)
        OptionParser.new do |opts|
          opts.banner = <<-TXT
    Usage: #{__FILE__} <component>:<command> [<args>] --[options]

    Components:
      aws
        Commands:
          bootstrap [<key=value>] Return values of keys (or all keys if none specified)

      service
        Commands:
          add       [<key=value>]
          config    <key=value>]
          deploy    [<key=value>]

          TXT

          opts.on('-c', '--cluster=CLUSTER_NAME', 'Name of the cluster in' \
           ' which to work in.') do |c|
            options[:cluster] = c
          end

          opts.on('-s', '--service=NAME', 'The service name to use.') do |s|
            options[:service] = s
          end

          opts.on('-p', '--params-file=PATH', 'May be used to pass parameters' \
            ' to a command via a JSON file rather than on the command line.' \
            ' Command line parameters take precedence.') do |p|
            options[:params_file] = p
          end
        end.parse!(cli_args)

        options
      end

      def _parse_params(kv_strings)
        params = {}

        kv_strings.each do |str|
          key, val = str.split('=', 2)

          if key[key.length - 2..-1] == '[]'
            key = key[0..-3]
            val = val.split(',')
          end

          if key.include?('.')
            keys = key.split('.').map(&:to_sym)
            inner = keys[0..-2].inject(params) { |h,k| h[k] ||= {} }
            inner[keys.last] = val
          else
            params[key.to_sym] = val
          end
        end

        params
      end

      def _merge_file_params(path, cli_params)
        path = File.expand_path(path)
        JSON.parse(File.read(path), symbolize_names: true).merge(cli_params)
      end
    end # Arguments
  end # CLI
end # Podbay