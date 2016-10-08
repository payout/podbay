module Podbay
  module Components
    module Aws::Resources
      RSpec.describe RDS do
        let(:rds) { RDS.new }

        describe '#client' do
          subject { rds.client }

          it { is_expected.to be_a ::Aws::RDS::Client }
        end # #client
      end # RDS
    end # Aws::Resources
  end # Components
end # Podbay
