module Podbay
  module Components
    module Aws::Resources
      RSpec.describe Base do
        let(:base) { Base.new }

        describe '#region' do
          subject { base.region }

          it { is_expected.to eq 'us-east-1' }

          context 'with environment variable set' do
            around do |ex|
              ENV['AWS_REGION'] = 'us-west-1'
              ex.run
              ENV['AWS_REGION'] = nil
            end

            it { is_expected.to eq 'us-west-1' }
          end
        end # #region

        describe '#tags_of' do
          subject { base.tags_of(resource) }

          let(:resource) { double('resource', tags: tags) }
          let(:tag) { Struct.new(:key, :value) }
          let(:tags) do
            [
              tag.new('az1', 'us-east-1c'),
              tag.new('az2', 'us-east-1d'),
              tag.new('cluster', 'test_cluster'),
            ]
          end

          it 'should convert the tags into a hash' do
            is_expected.to eq(
              az1: 'us-east-1c',
              az2: 'us-east-1d',
              cluster: 'test_cluster'
            )
          end

          context 'with empty tags' do
            let(:tags) { {} }
            it { is_expected.to eq({}) }
          end

          context 'with resource not responding to tags' do
            let(:resource) { double('resource') }

            it 'should raise an error' do
              expect { subject }.to raise_error 'resource cannot have tags'
            end
          end
        end # #tags_of

        describe 'method_missing' do
          it 'should allow instance methods to be called on the class' do
            expect(Base.region).to eq 'us-east-1'
            expect(Base.tags_of(double('tags', tags: {}))).to eq({})
          end

          context 'with resource_interface' do
            let(:resource_class) do
              Class.new(Base) do
                def resource_interface
                  Struct.new('Test', :test_method).new({})
                end
              end
            end

            it 'should send missing methods to the resource interface' do
              expect(resource_class.test_method).to eq({})
            end
          end # with resource_interface
        end # method_missing
      end # Base
    end # Aws::Resources
  end # Components
end # Podbay
