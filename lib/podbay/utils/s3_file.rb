require 'uri'
require 'aws-sdk'
require 'openssl'

class Podbay::Utils
  class S3File
    attr_reader :bucket
    attr_reader :key

    class << self
      def read(uri)
        _new_instance(uri).read
      end

      def write(uri, data)
        _new_instance(uri).write(data)
      end

      def mock(mock)
        @_mock = mock
        yield
      ensure
        @_mock = nil
      end

      private

      def _new_instance(uri)
        (@_mock || self).new(uri)
      end
    end # Class Methods

    def initialize(uri)
      uri = URI(uri)
      fail 'expected s3 uri' unless uri.scheme == 's3'
      @bucket = uri.host
      @key = uri.path[1..-1]
    end

    def write!(data)
      S3.put_object(
        acl: 'private',
        body: data,
        bucket: bucket,
        key: key,
        server_side_encryption: 'AES256',
        storage_class: 'STANDARD'
      )

      data
    end

    alias_method :write, :write!

    def read!
      S3.get_object(bucket: bucket, key: key).body.read
    rescue Aws::S3::Errors::NoSuchKey
      nil
    end

    alias_method :read, :read!
  end # S3File
end # Podbay::Utils
