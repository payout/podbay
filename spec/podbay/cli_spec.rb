module Podbay
  RSpec.describe CLI do
    let(:arguments) { CLI::Arguments.new(cli_str.split(' ')) }
    let(:cli_str) { '' }

    describe '::run_component_command' do
      subject { CLI.run_component_command(arguments) }

      context 'with invalid component name' do
        let(:cli_str) { 'invalid_component_name:deploy' }

        it 'should throw invalid component exception' do
          expect { subject }.to raise_error RuntimeError,
            "Invalid component name 'invalid_component_name'!"
        end
      end

      context 'with invalid command name' do
        let(:cli_str) { 'aws:invalid_command' }

        it 'should throw invalid component exception' do
          expect { subject }.to raise_error NoMethodError,
            a_string_starting_with("undefined method `invalid_command' for ")
        end
      end
    end # ::run_component_command

    describe '::run_component_command!' do
      subject { CLI.run_component_command!(component, arguments) }

      let(:cli_str) do
        "doesnotmatter:#{command} #{args.join(' ')} " \
          "#{params.map {|k,v| "#{k}=#{v}"}.join(' ')} " \
          "--cluster=#{cluster}"
      end

      let(:command) { 'my_command' }
      let(:args) { ['arg1', 'arg2'] }
      let(:params) { { key: 'value' } }
      let(:cluster) { 'my_cluster' }

      let(:component_instance) { double('Component Instance') }
      let(:component) { double('Component', new: component_instance) }

      after { subject }

      it 'should instantiate component with expected args' do
        allow(component_instance).to receive(command)
        expect(component).to receive(:new).with(cluster: cluster).once
      end

      it 'should call command method with expected args' do
        expect(component_instance).to receive(command)
          .with(*args, params).once
      end
    end # ::run_component_command!
  end # CLI
end # Podbay