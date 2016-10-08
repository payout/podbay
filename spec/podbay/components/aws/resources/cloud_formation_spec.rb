module Podbay
  module Components
    module Aws::Resources
      RSpec.describe CloudFormation do
        let(:cf) { CloudFormation.new }

        describe '#client' do
          subject { cf.client }

          it { is_expected.to be_a ::Aws::CloudFormation::Client }
        end # #client
      end # CloudFormation
    end # Aws::Resources
  end # Components
end # Base
