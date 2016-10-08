module Podbay
  RSpec.describe Components do
    describe '::list' do
      subject { Components.list }

      it 'should have expected components' do
        is_expected.to eq [
          Podbay::Components::Aws,
          Podbay::Components::Consul,
          Podbay::Components::Daemon,
          Podbay::Components::Help,
          Podbay::Components::Service,
          Podbay::Components::Version
        ]
      end
    end # ::list

    describe '::find_component' do
      subject { Components.find_component(name) }

      context "with name = ''" do
        let(:name) { '' }
        it { is_expected.to be nil }
      end

      context "with name = 'base'" do
        let(:name) { 'base' }
        it { is_expected.to be nil }
      end

      context "with name = 'cloud_base'" do
        let(:name) { 'cloud_base' }
        it { is_expected.to be nil }
      end

      context "with name = 'not_found'" do
        let(:name) { 'not_found' }
        it { is_expected.to be nil }
      end

      context "with name = 'aws'" do
        let(:name) { 'aws' }
        it { is_expected.to be Components::Aws }
      end

      context "with name = 'service'" do
        let(:name) { 'service' }
        it { is_expected.to be Components::Service }
      end

      context "with name = 'Aws'" do
        let(:name) { 'Aws' }
        it { is_expected.to be Components::Aws }
      end

      context "with name = 'AWS'" do
        let(:name) { 'AWS' }
        it { is_expected.to be Components::Aws }
      end
    end # ::find_component
  end # Components
end # Podbay
