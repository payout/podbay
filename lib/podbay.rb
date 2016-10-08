require 'active_support/all'
require 'podbay/version'
require 'podbay/monkey_patches'

module Podbay
  autoload(:Components, 'podbay/components')
  autoload(:Mixins,     'podbay/mixins')
  autoload(:CLI,        'podbay/cli')
  autoload(:Consul,     'podbay/consul')
  autoload(:Docker,     'podbay/docker')
  autoload(:Regex,      'podbay/regex')
  autoload(:Utils,      'podbay/utils')

  SERVER_INFO_PORT = 7329

  class Error < StandardError; end
  class ValidationError < Error; end
  class MissingResourceError < Error; end
  class PodbayGroupError < Error; end
  class ResourceWaiterError < Error; end
  class UnhealthyDeploymentError < Error; end
  class ConsulServerNotSyncedError < Error; end
  class TimeoutError < Error; end
  class ActionExpiredError < Error; end
  class ImageRetrieveError < Error; end
end # Podbay
