require 'aws-sdk'

module Podbay
  class Utils
    class S3
      include Mixins::Mockable

      def bucket(name)
        ::Aws::S3::Bucket.new(name, client: _s3)
      end

      def object_exists?(bucket_name, key)
        key = key.gsub(/\A\//, '')
        bucket(bucket_name).object(key).exists?
      end

      def method_missing(meth, *args, &block)
        _s3.public_send(meth, *args, &block)
      end

      def _s3
        @_s3 ||= ::Aws::S3::Client.new(region: EC2.region)
      end
    end # S3
  end # Utils
end # Podbay
