module Podbay
  module Components
    module Aws::Resources
      RSpec.describe IAM do
        let(:iam) { IAM.new }

        describe '#client' do
          subject { iam.client }

          it { is_expected.to be_a ::Aws::IAM::Client }
        end # #client
      end # IAM
    end # Aws::Resources
  end # Components
end # Podbay
