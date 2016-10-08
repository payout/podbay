require 'tmpdir'
require 'fileutils'

module Podbay
  module CLI
    RSpec.describe Arguments do
      let(:cli_str) { '' }
      let(:arguments) { Arguments.new(cli_str.split(' ')) }

      describe '#new' do
        subject { arguments }

        def assert_args_equals(component, command, options, args)
          is_expected.to have_attributes(
            component: component,
            command: command,
            options: options,
            args: args
          )
        end

        context 'with no component:command passed in' do
          let(:cli_str) { '' }

          it 'should default to help:execute' do
            assert_args_equals('help', 'execute', {}, [])
          end
        end

        context 'with method : separator' do
          context 'with one `:` in method name' do
            let(:cli_str) { 'aws:config:delete' }

            it 'should correctly convert to the method name' do
              assert_args_equals('aws', 'config_delete', {}, [])
            end
          end

          context 'with multiple `:` in method name' do
            let(:cli_str) { 'aws:config:delete:one' }

            it 'should correctly convert to the method name' do
              assert_args_equals('aws', 'config_delete_one', {}, [])
            end
          end
        end

        context 'with options set' do
          context 'with only cluster set' do
            let(:cli_str) { 'aws:bootstrap --cluster=test-cluster' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {cluster: 'test-cluster'}, [])
            end
          end

          context 'with only cluster set with short notation' do
            let(:cli_str) { 'aws:bootstrap -c test-cluster' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {cluster: 'test-cluster'}, [])
            end
          end

          context 'with only service set' do
            let(:cli_str) { 'aws:bootstrap --service=test-service' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {service: 'test-service'}, [])
            end
          end

          context 'with only service set with short notation' do
            let(:cli_str) { 'aws:bootstrap -s test-service' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {service: 'test-service'}, [])
            end
          end

          context 'with multiple options set' do
            let(:cli_str) do
              'aws:bootstrap --cluster=test-cluster --service=test-service'
            end

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap',
                {cluster: 'test-cluster', service: 'test-service'}, []
              )
            end
          end

          context 'with invalid option setting' do
            let(:cli_str) { 'aws:bootstrap --random-option=test-value-1' }

            it 'should throw arguments exception' do
              expect { subject }.to raise_error OptionParser::InvalidOption,
                'invalid option: --random-option=test-value-1'
            end
          end
        end # with options set

        context 'with params set' do
          context 'with single param set' do
            let(:cli_str) { 'aws:bootstrap role=server' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {}, [{role: 'server'}])
            end

            context 'with array of values' do
              let(:cli_str) { 'aws:bootstrap roles[]=this,that' }

              it 'should parse arguments' do
                assert_args_equals('aws', 'bootstrap', {},
                  [{roles: ['this', 'that']}])
              end
            end
          end # with single param set

          context 'with single nested param set' do
            let(:cli_str) { 'aws:bootstrap param.key=value' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {},
                [{param: {key: 'value'}}])
            end

            context 'with array of values' do
              let(:cli_str) { 'aws:bootstrap role.profiles[]=this,that' }

              it 'should parse arguments' do
                assert_args_equals('aws', 'bootstrap', {},
                  [{role: { profiles: ['this', 'that'] } }])
              end
            end
          end # with single nested param set

          context 'with multiple params set' do
            let(:cli_str) { 'aws:bootstrap role=server expect=3' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {},
                [{role: 'server', expect: '3'}])
            end
          end

          context 'with multiple nested params set' do
            let(:cli_str) { 'aws:bootstrap a.b=c a.d=e a.f=g' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {},
                [{a: {b: 'c', d: 'e', f: 'g'}}])
            end
          end

          context 'with multiple doubly nested params set' do
            let(:cli_str) { 'aws:bootstrap a.b.c=d a.e.f=g a.h=i' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'bootstrap', {},
                [{a: {b: {c: 'd'}, e: {f: 'g'}, h: 'i'}}])
            end
          end
        end # with params set

        context 'without options or params set' do
          let(:cli_str) { 'aws:bootstrap' }

          it 'should parse arguments' do
            assert_args_equals('aws', 'bootstrap', {}, [])
          end
        end

        context 'with args set' do
          context 'with single arg set' do
            let(:cli_str) { 'aws:deploy test_image_name' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'deploy', {}, ['test_image_name'])
            end
          end

          context 'with multiple arg set' do
            let(:cli_str) { 'aws:deploy test_image_name test_arg' }

            it 'should parse arguments' do
              assert_args_equals('aws', 'deploy', {},
                ['test_image_name', 'test_arg'])
            end
          end
        end # with args set

        context 'with args and params set' do
          let(:cli_str) { 'aws:deploy test_image_name role=server' }

          it 'should parse arguments' do
            assert_args_equals('aws', 'deploy', {},
              ['test_image_name', {role: 'server'}])
          end
        end

        context 'with args, params, and options set' do
          let(:cli_str) do
            'aws:deploy test_image_name role=server --cluster=test-cluster'
          end

          it 'should parse arguments' do
            assert_args_equals('aws', 'deploy', {cluster: 'test-cluster'},
              ['test_image_name', {role: 'server'}])
          end
        end

        context 'with options and file params set' do
          let(:temp_file) { "#{Dir.mktmpdir}/test" }
          let(:cli_str) do
            "aws:db_setup --cluster=test-cluster --params-file=#{temp_file}"
          end

          before do
            File.write(
              temp_file, '{"username": "admin1", "password": "test1234"}'
              )
          end

          it 'should parse arguments' do
            assert_args_equals('aws', 'db_setup', {params_file: temp_file,
              cluster: "test-cluster"},
              [{username: 'admin1', password: 'test1234'}])
          end
        end

        context 'with options, file params and cli params set' do
          let(:temp_file) { "#{Dir.mktmpdir}/test" }
          let(:cli_str) do
            "aws:db_setup --cluster=test-cluster  --params-file=#{temp_file} " \
              "username=admin1"
          end

          before do
            File.write(
              temp_file, '{"username": "admin0", "password": "test1234"}'
              )
          end

          it 'should give params presedence' do
            assert_args_equals('aws', 'db_setup', {params_file: temp_file,
              cluster: "test-cluster"},
              [{username: 'admin1', password: 'test1234'}])
          end
        end
      end # #new

      describe '#command' do
        subject { arguments.command }

        context 'with command set' do
          let(:cli_str) { 'aws:deploy' }
          it { is_expected.to eq 'deploy' }
        end

        context 'with no command set' do
          let(:cli_str) { 'aws' }
          it { is_expected.to eq 'execute' }
        end
      end # #command

      describe '#component' do
        subject { arguments.component }

        context 'with command set' do
          let(:cli_str) { 'aws:deploy' }
          it { is_expected.to eq 'aws' }
        end

        context 'with no command set' do
          let(:cli_str) { '' }
          it { is_expected.to eq 'help' }
        end
      end # #component
    end # Arguments
  end # CLI
end # Podbay