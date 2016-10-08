require 'active_support/inflector'

module Podbay
  module Components
    autoload(:Base,     'podbay/components/base')
    autoload(:Service,  'podbay/components/service')
    autoload(:Aws,      'podbay/components/aws')
    autoload(:Daemon,   'podbay/components/daemon')
    autoload(:Consul,   'podbay/components/consul')
    autoload(:Help,     'podbay/components/help')
    autoload(:Version,  'podbay/components/version')

    class << self
      def list
        constants.sort.map { |c| const_get(c) }
          .select { |c| c.is_a?(Class) && c < Base }
      end

      def find_component(name)
        list.find { |m| m.to_s.split('::').last == name.downcase.camelcase }
      end
    end # Class Methods
  end # Components
end # Podbay
