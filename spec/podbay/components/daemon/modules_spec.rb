class Podbay::Components::Daemon
  RSpec.describe Modules do
    let(:modules) { Modules.new }

    describe '#load' do
      subject { modules.load(name) }

      context 'with name = "registrar"' do
        let(:name) { 'registrar' }
        it { is_expected.to be Modules::Registrar }
      end

      context 'with name = :registrar' do
        let(:name) { :registrar }
        it { is_expected.to be Modules::Registrar }
      end

      context 'with name = "service_router"' do
        let(:name) { 'service_router' }
        it { is_expected.to be Modules::ServiceRouter }
      end

      context 'with name = :static_services' do
        let(:name) { :static_services }
        it { is_expected.to be Modules::StaticServices }
      end

      context 'with name = :listener' do
        let(:name) { :listener }
        it { is_expected.to be Modules::Listener }
      end
    end # #load
  end # Modules
end # Podbay::Components::Daemon
