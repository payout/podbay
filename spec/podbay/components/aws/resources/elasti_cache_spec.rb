module Podbay
  module Components
    module Aws::Resources
      RSpec.describe ElastiCache do
        let(:elasticache) { ElastiCache.new }

        def aws_error(error_name)
          ::Aws::ElastiCache::Errors.error_class(error_name).new('','')
        end

        it 'should send missing methods to the client' do
          expect(elasticache).to receive(:client)
            .and_return(double('client', test_method: 'test'))
          expect(elasticache.test_method).to eq 'test'
        end

        describe '#client' do
          subject { elasticache.client }

          it { is_expected.to be_a ::Aws::ElastiCache::Client }
        end # #client
      end # ElastiCache
    end # Aws::Resources
  end # Components
end # Podbay
