require 'yaml'

module Podbay
  module Components
    class Help < Base
      include ERB::Util

      MAX_LINE_LENGTH = 80
      LEFT_PADDING    = 2
      COLUMN_PADDING  = 3

      def execute(command = nil, *_)
        return _generate_general_help unless command

        @_component, @_method = Utils.parse_cli_component_and_method(command)
        @_method ||= 'execute'

        unless _help_params
          puts "Help params for #{@_component}:#{@_method} not found."
          return
        end

        _generate_command_help
      end

      private

      def _usage_str
        starting_str = "usage: podbay #{@_component}"
        starting_str += ":#{@_method}" unless @_method == 'execute'

        str = [starting_str]
        if _help_params['args']
          str << _help_params['args'].map(&:upcase).join(' ')
        end
        str << '[<params>]' if _help_params['params']
        if _help_params['options']
          str << _help_params['options'].map { |o| "--#{o}=#{o.upcase}_VAL" }
        end

        str.join(' ')
      end

      def _split_line_on_length(line, indent_size = 2, max_length = MAX_LINE_LENGTH)
        split_lines = line.split(' ').reduce([[]]) do |lines, word|
          if (lines.last.join(' ').length + word.length) < max_length
            lines.last << word
          else
            lines << [word]
          end

          lines
        end

        split_lines.map { |l| l.join(' ') }.join("\n" + ' ' * indent_size)
      end

      def _generate_param_rows
        _help_params['params'].map do |param, value|
          line = _generate_param_title_column(param, value).blue
          next line unless (desc = value['desc'])

          desc = 'REQUIRED - '.green + desc if value['required']
          line + _generate_column(desc,
            LEFT_PADDING + _min_param_title_column_length)
        end
      end

      def _generate_param_title_column(key, params)
        key += "=#{params['default']}" if params['default']
        key.ljust(_min_param_title_column_length)
      end

      def _param_titles
        @__param_titles ||= _help_params['params'].map do |key, v|
          key += "=#{v['default']}" if v['default']
          key
        end
      end

      def _min_param_title_column_length
        @__param_title_length ||= _min_column_length(_param_titles)
      end

      def _min_cmd_title_column_length
        @__cmd_title_length ||= _min_column_length(_all_commands)
      end

      def _min_column_length(strings)
        strings.reduce(0) do |longest, s|
          length = s.length + COLUMN_PADDING
          length > longest ? length : longest
        end
      end

      def _all_commands
        _help_file.map do |component, v|
          v.map { |command, _| "#{component}:#{command}" }
        end
        .flatten
      end

      def _generate_command_rows
        _help_file.map do |component, v|
          v.map do |command, cmd_v|
            line = component.dup
            line << ":#{command}" unless command == 'execute'
            line = line.ljust(_min_cmd_title_column_length).blue
            line + _generate_column(cmd_v['desc'],
              LEFT_PADDING + _min_cmd_title_column_length)
          end
        end
      end

      def _generate_column(line, used_row_length)
        if (used_row_length + line.decolorize.length) > MAX_LINE_LENGTH

          max_length = MAX_LINE_LENGTH - used_row_length
          _split_line_on_length(line, used_row_length, max_length)
        else
          line
        end
      end

      def _help_params
        begin
          @_help_object ||= _help_file[@_component][@_method]
        rescue NoMethodError
          nil
        end
      end

      def _help_file
        @__help_file ||= YAML.load_file(File.expand_path(
          '../../../../data/help.yml', __FILE__))
      end

      def _generate_general_help
        lines = [
          'usage: podbay [help] <command> [<args>]' \
            ' [<params>] [--cluster=<name>]',
          '              [--service=name]',
          '',
          'Available Podbay commands:',
          _generate_command_rows
        ]

        _print_help(lines)
      end

      def _generate_command_help
        lines = [
          _usage_str,
          '',
          _split_line_on_length(_help_params['desc'])
        ]

        lines += ["", "Available params are:"] if _help_params['params']
        lines << _generate_param_rows if _help_params['params']

        _print_help(lines)
      end

      def _print_help(lines)
        puts ' ' * LEFT_PADDING + lines.join("\n" + ' ' * LEFT_PADDING)
      end
    end # Help
  end # Components
end # Podbay
