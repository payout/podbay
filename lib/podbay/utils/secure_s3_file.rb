require 'uri'
require 'aws-sdk'
require 'openssl'

class Podbay::Utils
  class SecureS3File < S3File
    attr_accessor :kms_key_id

    KMS_CONTEXT = { 'podbay' => 'SecureS3File' }.freeze

    class << self
      def write(uri, data, kms_key_id = nil)
        f = _new_instance(uri)
        f.kms_key_id = kms_key_id if kms_key_id
        f.write(data)
      end
    end # Class Methods

    def write(data)
      # Attempt to determine the kms_key_id by reading the file.
      # If this is a new file, then an exception will be raised later in the
      # _gen_key method since there is no kms_key_id.
      read unless kms_key_id
      encrypted_data = _encrypt(data)
      write!(encrypted_data)
    end

    def read
      body = read!
      _decrypt(body) if body
    end

    private

    def _kms
      @__kms ||= Aws::KMS::Client.new(region: EC2.region)
    end

    def _encrypt(data)
      key, encrypted_key = _gen_key
      key_len = encrypted_key.length
      [key_len].pack('N') + encrypted_key + _aes256_encrypt(key, data)
    end

    def _decrypt(data)
      data.force_encoding('BINARY')
      key_len = data[0..3].unpack('N').first
      encrypted_key = data[4..(key_len + 3)]
      encrypted_data = data[(key_len + 4)..-1]

      key = _decrypt_key(encrypted_key)
      _aes256_decrypt(key, encrypted_data)
    end

    ##
    # Encrypts the data using the key, saving the randomly generated IV as the
    # first 16 bytes of the returned data.
    def _aes256_encrypt(key, data)
      encryptor = OpenSSL::Cipher::AES256.new(:CBC).encrypt
      encryptor.key = key
      encryptor.iv = iv = encryptor.random_iv

      encrypted_data = encryptor.update(data) + encryptor.final

      iv + encrypted_data
    end

    ##
    # Decrypts the data using the key.
    #
    # Expects the first 16 bytes of the data to be the randomly generated IV
    # from the _aes356_encrypt method. It will need this to correctly decrypt
    # the subsequent data.
    def _aes256_decrypt(key, data)
      data.force_encoding('BINARY')
      iv = data[0..15]
      encrypted_data = data[16..-1]

      decryptor = OpenSSL::Cipher::AES256.new(:CBC).decrypt
      decryptor.key = key
      decryptor.iv = iv

      decryptor.update(encrypted_data) + decryptor.final
    end

    def _gen_key
      fail 'missing kms_key_id' unless kms_key_id

      resp = _kms.generate_data_key(
        key_id: kms_key_id,
        encryption_context: KMS_CONTEXT,
        key_spec: "AES_256"
      )

      [resp.plaintext, resp.ciphertext_blob.force_encoding('BINARY')]
    end

    def _decrypt_key(encrypted_key)
      resp = _kms.decrypt(
        ciphertext_blob: encrypted_key,
        encryption_context: KMS_CONTEXT
      )

      @kms_key_id = resp.key_id
      resp.plaintext
    end
  end # SecureS3File
end # Podbay::Utils
