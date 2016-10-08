module Podbay
  class Components::Aws
    module Resources
      autoload(:Base,           'podbay/components/aws/resources/base')
      autoload(:EC2,            'podbay/components/aws/resources/ec2')
      autoload(:AutoScaling,    'podbay/components/aws/resources/auto_scaling')
      autoload(:IAM,            'podbay/components/aws/resources/iam')
      autoload(:ELB,            'podbay/components/aws/resources/elb')
      autoload(:RDS,            'podbay/components/aws/resources/rds')
      autoload(:CloudFormation, 'podbay/components/aws/resources/cloud_formation')
      autoload(:ElastiCache,    'podbay/components/aws/resources/elasti_cache')
    end # Resources
  end # Components::Aws
end # Podbay