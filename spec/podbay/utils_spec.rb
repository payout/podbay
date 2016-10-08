require 'socket'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'tempfile'
require 'digest'
require 'zlib'

module Podbay
  RSpec.describe Utils do
    describe '::parse_cli_component_and_method' do
      subject { Utils.parse_cli_component_and_method(str) }

      context 'with str=aws' do
        let(:str) { 'aws' }
        it { is_expected.to eq ['aws', nil] }
      end

      context 'with str=aws:bootstrap' do
        let(:str) { 'aws:bootstrap' }
        it { is_expected.to eq ['aws', 'bootstrap'] }
      end

      context 'with str=aws:config:delete' do
        let(:str) { 'aws:config:delete' }
        it { is_expected.to eq ['aws', 'config_delete'] }
      end
    end # ::parse_cli_component_and_method

    describe '::gunzip_file' do
      subject { Utils.gunzip_file(gzipped_file_path) }

      let(:gzipped_file_path) { "#{Dir.mktmpdir}/gzipped_file" }

      before do
        Zlib::GzipWriter.open(gzipped_file_path) do |gz|
          gz.write('some_test_data')
        end
      end

      it 'should extract file with contents intact' do
        subject
        expect(File.read(gzipped_file_path)).to eq 'some_test_data'
      end
    end # gunzip_file

    describe '::valid_sha256' do
      subject { Utils.valid_sha256?(temp_file_path, sha256) }

      let(:temp_file_path) { Tempfile.new('test_file').path }
      let(:sha256) { Digest::SHA256.file(temp_file_path).hexdigest }

      before do
        File.open(temp_file_path, 'w') do |f|
          f.write('some_test_data')
        end
      end

      context 'with the matching sha256' do
        it { is_expected.to eq true }
      end # with the matching sha256

      context 'with another non-matching sha256' do
        let(:sha256) {
          Digest::SHA256.file(Tempfile.new('other_file').path).hexdigest
        }
        it { is_expected.to eq false }
      end # with another non-matching sha256
    end # valid_sha256

    describe '::create_directory_path' do
      subject { Utils.create_directory_path(path) }

      let(:temp_dir) { "#{Dir.mktmpdir}" }
      let(:path) { "#{temp_dir}/to/test/dir" }

      it 'should create a directory' do
        subject
        expect(File.directory?(path)).to be true
      end
    end # create_directory_path

    describe '::rm', :rm do
      subject { Utils.rm(path) }

      let(:tempfile) { Tempfile.new('utils_rm_test') }
      let(:path) { tempfile.path }

      it 'should remove the file' do
        expect(File.exists?(path)).to be true
        subject
        expect(File.exists?(path)).to be false
      end
    end

    describe '::add_to_json_file' do
      subject { Utils.add_to_json_file(key, value, path) }

      let(:key) { 'key' }
      let(:value) { 'value' }
      let(:file) { Tempfile.new('add_to_json_file') }
      let(:path) { file.path }
      let(:path_contents) { File.read(file.path) }

      before do
        File.write(file.path, initial_contents)
        file.close
        subject
      end

      after { file.unlink }

      context 'with an empty file' do
        let(:initial_contents) { '' }

        it 'should add an entry' do
          expect(JSON.parse(path_contents)).to eq JSON.parse(
            '{"key": "value"}'
          )
        end
      end # with an empty file

      context 'with an empty json hash file' do
        let(:initial_contents) { '{}' }

        it 'should add an entry' do
          expect(JSON.parse(path_contents)).to eq JSON.parse(
            '{"key": "value"}'
          )
        end
      end # with an empty json hash file

      context 'with a file with a existing different key/value' do
        let(:initial_contents) { '{"existing_key": "existing_value"}' }

        it 'should add an additional entry' do
          expect(JSON.parse(path_contents)).to eq JSON.parse(
            '{"existing_key": "existing_value", "key": "value"}'
          )
        end
      end # with a file with a existing different key/value

      context 'with a file with a existing key' do
        let(:initial_contents) { "{\"key\": \"#{existing_value}\"}" }
        context 'with existing same value' do
          let(:existing_value) { 'value' }
          it 'should overwrite the existing entry' do
            expect(JSON.parse(path_contents))
              .to eq JSON.parse('{"key": "value"}')
          end
        end # with existing same value

        context 'with existing different value' do
          let(:existing_value) { 'different_value' }
          it 'should should overwriting the existing entry' do
            expect(JSON.parse(path_contents))
              .to eq JSON.parse('{"key": "value"}')
          end
        end # with existing different value
      end # with a file with a existing key
    end # ::add_to_json_file

    describe '::split_cidr' do
      subject { Utils.split_cidr(cidr) }
      let(:cidr) { '10.0.0.0/16' }
      it { is_expected.to eq [10, 0, 0, 0, 16] }
    end # ::split_cidr

    describe '::join_cidr' do
      subject { Utils.join_cidr(octets, mask) }

      let(:octets) { [] }
      let(:mask) { 16 }

      context 'with no octets passed in' do
        it { is_expected.to eq '0.0.0.0/16' }
      end

      context 'with 1 octet passed in' do
        let(:octets) { [10] }
        it { is_expected.to eq '10.0.0.0/16' }
      end

      context 'with all octets passed in' do
        let(:octets) { [1, 2, 3, 4] }
        it { is_expected.to eq '1.2.3.4/16' }
      end

      context 'with nested arrays' do
        let(:octets) { [1, 2, [3, [4]]] }
        it { is_expected.to eq '1.2.3.4/16' }
      end

      context 'with mask=0' do
        let(:mask) { 0 }
        it { is_expected.to eq '0.0.0.0/0' }
      end
    end # ::join_cidr

    describe '::pick_available_cidr' do
      subject { Utils.pick_available_cidr(net_cidr, unavailable_cidrs, opts) }
      let(:opts) { {} }
      let(:net_cidr) { '10.0.0.0/16' }
      let(:unavailable_cidrs) { [] }

      context 'with default options' do
        it { is_expected.to eq '10.0.1.0/24' }
      end # with default options

      context 'with mask=0' do
        let(:opts) { { mask: 0 } }
        it 'should raise an error' do
          expect { subject }.to raise_error 'mask must be within (16..31)'
        end
      end

      context 'with mask=15' do
        let(:opts) { { mask: 15 } }
        it 'should raise an error' do
          expect { subject }.to raise_error 'mask must be within (16..31)'
        end
      end

      context 'with mask=32' do
        let(:opts) { { mask: 32 } }
        it 'should raise an error' do
          expect { subject }.to raise_error 'mask must be within (16..31)'
        end
      end

      context 'with mask=24' do
        let(:opts) { { mask: 24 } }

        context 'with no used cidrs' do
          it { is_expected.to eq '10.0.1.0/24' }
        end

        context 'with some used cidrs' do
          let(:unavailable_cidrs) { ['10.0.1.0/24', '10.0.3.0/24'] }
          it { is_expected.to eq '10.0.5.0/24' }
        end

        context 'with 1 cidr left' do
          let(:unavailable_cidrs) do
            (1..253).step(2).map { |i| "10.0.#{i}.0/24" }
          end
          it { is_expected.to eq '10.0.255.0/24' }
        end

        context 'with all cidrs used' do
          let(:unavailable_cidrs) do
            (1..255).step(2).map { |i| "10.0.#{i}.0/24" }
          end
          it { is_expected.to eq nil }
        end
      end # with mask=24

      context 'with mask=28' do
        let(:opts) { { mask: 28 } }

        context 'with no used cidrs' do
          it { is_expected.to eq '10.0.1.0/28' }
        end

        context 'with some used cidrs' do
          let(:unavailable_cidrs) { ['10.0.1.0/28', '10.0.1.16/28'] }
          it { is_expected.to eq '10.0.1.32/28' }
        end

        context 'with one inner gap at end' do
          let(:unavailable_cidrs) do
            ['10.0.1.0/28', '10.0.1.16/28', '10.0.1.32/28', '10.0.1.48/28',
             '10.0.1.64/28', '10.0.1.80/28', '10.0.1.96/28', '10.0.1.112/28',
             '10.0.1.128/28', '10.0.1.144/28', '10.0.1.160/28',
             '10.0.1.176/28', '10.0.1.192/28', '10.0.1.208/28',
             '10.0.1.224/28']
          end

          it { is_expected.to eq '10.0.1.240/28' }
        end

        context 'with one inner in the middle' do
          let(:unavailable_cidrs) do
            ['10.0.1.0/28', '10.0.1.16/28', '10.0.1.32/28', '10.0.1.48/28',
             '10.0.1.64/28', '10.0.1.80/28', '10.0.1.96/28', '10.0.1.112/28',
             '10.0.1.128/28', '10.0.1.160/28', '10.0.1.176/28', '10.0.1.192/28',
             '10.0.1.208/28', '10.0.1.224/28', '10.0.1.240/28']
          end

          it { is_expected.to eq '10.0.1.144/28' }
        end

        context 'with no inner gaps' do
          let(:unavailable_cidrs) do
            ['10.0.1.0/28', '10.0.1.16/28', '10.0.1.32/28', '10.0.1.48/28',
             '10.0.1.64/28', '10.0.1.80/28', '10.0.1.96/28', '10.0.1.112/28',
             '10.0.1.128/28', '10.0.1.144/28', '10.0.1.160/28',
             '10.0.1.176/28', '10.0.1.192/28', '10.0.1.208/28',
             '10.0.1.224/28', '10.0.1.240/28']
          end

          it { is_expected.to eq '10.0.3.0/28' }
        end

        context 'with mixed masks' do
          let(:unavailable_cidrs) do
            ['10.0.1.0/28', '10.0.1.16/28', '10.0.1.32/28', '10.0.1.48/28',
             '10.0.1.64/28', '10.0.1.80/28', '10.0.1.96/28', '10.0.1.112/28',
             '10.0.1.128/28', '10.0.1.144/28', '10.0.1.160/28',
             '10.0.1.176/28', '10.0.1.192/28', '10.0.1.208/28',
             '10.0.1.224/28', '10.0.1.240/28', '10.0.3.0/24']
          end

          it { is_expected.to eq '10.0.5.0/28' }
        end

        context 'with all cidrs used' do
          let(:unavailable_cidrs) do
            (1..255).step(2).map { |i| "10.0.#{i}.0/24" }
          end
          it { is_expected.to eq nil }
        end
      end # with mask=28

      context 'with dmz=true' do
        let(:opts) { { dmz: true } }

        context 'with no used cidrs' do
          it { is_expected.to eq '10.0.0.0/24' }
        end

        context 'with some used cidrs' do
          let(:unavailable_cidrs) do
            ['10.0.0.0/24', '10.0.1.0/24', '10.0.2.0/24', '10.0.3.0/24']
          end
          it { is_expected.to eq '10.0.4.0/24' }
        end

        context 'with all cidrs used' do
          let(:unavailable_cidrs) do
            (0..254).step(2).map { |i| "10.0.#{i}.0/24" }
          end
          it { is_expected.to eq nil }
        end
      end # with dmz=true
    end # ::pick_available_cidr

    describe '::hostname', :hostname do
      subject { Utils.hostname }
      it { is_expected.to eq Socket.gethostname }
    end # ::hostname

    describe '::timestamp' do
      subject { Utils.timestamp }

      it { is_expected.to match(/\A\d{4}\d{2}\d{2}\d{2}\d{2}\d{2}\z/) }
    end # ::timestamp

    describe '::podbay_info' do
      subject { utils.podbay_info(ip_address, path, timeout) }

      let(:utils) { Utils.new }
      let(:ip_address) { '10.2.3.4' }
      let(:path) { 'consul_info' }
      let(:timeout) { 1 }
      let(:response) { double(body: body) }
      let(:body) { '{}' }

      before do
        allow(utils).to receive(:get_request).and_return(response)
      end

      context 'with connection error' do
        before do
          allow(utils).to receive(:get_request).and_raise(Errno::ECONNREFUSED)
        end

        it 'should raise an error' do
          expect { subject }.to raise_error(Errno::ECONNREFUSED)
        end
      end # with connection error

      context 'with successful request' do
        let(:body) { '{"check_monitors":0}' }

        it { is_expected.to eq(check_monitors: 0) }

        it 'should make the request to the correct url' do
          expect(utils).to receive(:get_request)
            .with('http://10.2.3.4:7329/consul_info', timeout: timeout)
          subject
        end
      end
    end # ::podbay_info

    describe '::prompt_question' do
      subject { Utils.prompt_question(question) }

      before do
        $stdin = double('stdin')
        allow($stdin).to receive(:gets)
          .and_return(*prompt_responses.map { |r| "#{r}\n" })
      end

      after { $stdin = STDIN }

      let(:question) { 'Is it time?' }
      let(:prompt_responses) { ['y'] }

      context 'with prompt_responses = y' do
        let(:prompt_responses) { ['y'] }
        it { is_expected.to eq true }
      end

      context 'with prompt_responses = n' do
        let(:prompt_responses) { ['n'] }
        it { is_expected.to eq false }
      end

      context 'with prompt_responses = Y' do
        let(:prompt_responses) { ['Y'] }
        it { is_expected.to eq true }
      end

      context 'with prompt_responses = N' do
        let(:prompt_responses) { ['N'] }
        it { is_expected.to eq false }
      end

      context 'with prompt_responses = bad_response, y' do
        let(:prompt_responses) { ['bad_response', 'y'] }
        it { is_expected.to eq true }

        it 'should prompt twice' do
          expect($stdin).to receive(:gets).twice
          subject
        end
      end
    end # ::prompt_question

    describe '::prompt_choice' do
      subject { Utils.prompt_choice(question, *choices) }

      let(:question) { 'What should we do next?' }
      let(:choices) { ['a', 'b', 'c'] }

      before do
        $stdin = double('stdin')
        allow($stdin).to receive(:gets)
          .and_return(*prompt_responses.map { |r| "#{r}\n" })
      end

      after { $stdin = STDIN }

      context 'with prompt_responses = 0, 1' do
        let(:prompt_responses) { [0, 1] }

        it 'should prompt twice' do
          expect($stdin).to receive(:gets).twice
          subject
        end
      end

      context 'with prompt_responses = 4, 1' do
        let(:prompt_responses) { [4, 1] }

        it 'should prompt twice' do
          expect($stdin).to receive(:gets).twice
          subject
        end
      end

      context 'with prompt_responses = 1' do
        let(:prompt_responses) { [1] }
        it { is_expected.to eq 'a' }
      end

      context 'with prompt_responses = 2' do
        let(:prompt_responses) { [2] }
        it { is_expected.to eq 'b' }
      end

      context 'with prompt_responses = 3' do
        let(:prompt_responses) { [3] }
        it { is_expected.to eq 'c' }
      end
    end # ::prompt_choice
  end # Docker
end # Podbay
