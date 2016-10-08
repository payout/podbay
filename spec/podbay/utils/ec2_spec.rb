module Podbay
  class Utils
    RSpec.describe EC2 do
      let(:ec2) { EC2.new }

      describe '#identity' do
        subject { ec2.identity }

        before do
          allow(ec2).to receive(:`).with(
            'curl http://169.254.169.254/latest/dynamic/instance-identity/' \
            'document 2> /dev/null'
          ).and_return(identity_resp)
        end

        let(:identity_resp) do
%{
{
  "devpayProductCodes" : null,
  "privateIp" : "10.0.1.2",
  "availabilityZone" : "us-east-1c",
  "accountId" : "1234",
  "billingProducts" : null,
  "instanceType" : "t2.small",
  "region" : "us-east-1"
}
}
        end

        it { is_expected.to eq(JSON.parse(identity_resp)) }
      end # #identity

      describe '#region' do
        subject { ec2.region }

        context 'with AWS_REGION env var' do
          around do |ex|
            ENV['AWS_REGION'] = 'us-east-1'
            ex.run
            ENV['AWS_REGION'] = nil
          end

          it { is_expected.to eq 'us-east-1' }
        end # with AWS_REGION env var

        context 'without AWS_REGION env var' do
          before do
            allow(ec2).to receive(:identity).and_return(identity)
          end

          let(:identity) do
            {
              'region' => 'us-west-1'
            }
          end

          it { is_expected.to eq 'us-west-1' }
        end
      end # #region
    end # EC2
  end # Utils
end # Podbay