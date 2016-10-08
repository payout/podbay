module Podbay::Regex
  CIDR = %r{(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}
    ([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])
    (\/([0-9]|[1-2][0-9]|3[0-2]))}x.freeze

  CIDR_VALIDATOR = /\A#{CIDR}\z/.freeze
  CIDR_LIST_VALIDATOR = /\A(#{CIDR},)*#{CIDR}\z/.freeze
end
