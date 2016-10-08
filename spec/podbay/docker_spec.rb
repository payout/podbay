module Podbay
  RSpec.describe Docker do
    let(:docker) { Docker.new }
    around { |ex| docker.mock_container(container_mock) { ex.run } }
    let(:container_mock) { double('container mock') }
    after { subject rescue nil }

    describe '::pull' do
      subject { docker.pull(name, tag) }

      let(:name) { 'name' }
      let(:tag) { 'tag' }

      it 'should execute the docker pull command' do
        expect(docker).to receive(:system).with('docker pull name:tag')
      end
    end # ::pull

    describe '::load' do
      subject { docker.load(path) }

      let(:path) { '/var/podbay/images/12345678' }

      it 'should execute the docker load command' do
        expect(docker).to receive(:system).with('docker load --input' \
          ' /var/podbay/images/12345678')
      end
    end # ::load

    describe '::inspect_container' do
      subject { docker.inspect_container(container_id) }
      let(:container_id) { '59d9ec2e9892' }

      # it 'should make expected requests to docker-api' do
      #   instance_mock = double('container instance')
      #   expect(container_mock).to receive(:get).with(container_id).once
      #     .and_return(instance_mock)
      #   expect(instance_mock).to receive(:info).with(no_args).once
      # end

      it 'should execute docker inspect command' do
        expect(docker).to receive(:`).with("docker inspect #{container_id} " \
          "2> /dev/null").once.and_return('{}')
      end
    end # ::inspect_container

    describe '::ready?', :ready? do
      subject { docker.ready? }

      let(:all_containers) { [] }

      before do
        allow(container_mock).to receive(:all).and_return(all_containers)
      end

      context 'with docker returning nil' do
        let(:all_containers) { nil }

        it 'should raise error' do
          expect { subject }.to raise_error 'received nil from _container.all'
        end
      end

      context 'with docker returning no containers' do
        let(:all_containers) { [] }
        it { is_expected.to be true }
      end

      context 'with Excon::Errors::SocketError' do
        before do
          allow(container_mock).to receive(:all)
            .and_raise(Excon::Errors::SocketError)
        end

        it { is_expected.to be false }
      end
    end # ::ready?
  end # Docker
end # Podbay
