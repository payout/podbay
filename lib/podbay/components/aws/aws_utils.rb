module Podbay
  class Components::Aws
    module AwsUtils
      class << self
        def cleanup_resources(*resources)
          resources.each do |resource|
            next unless resource

            case resource
            when Array
              cleanup_resources(*resource)
            else
              resource.delete
            end
          end
        end

        def default_database_port(engine)
          {
            'MySQL' => 3306,
            'mariadb' => 3306,
            'oracle-se1' => 1521,
            'oracle-se' => 1521,
            'oracle-ee' => 1521,
            'sqlserver-ee' => 1433,
            'sqlserver-se' => 1433,
            'sqlserver-ex' => 1433,
            'sqlserver-web' => 1433,
            'postgres' => 5432,
            'aurora' => 3306
          }[engine] or fail "no default port for engine #{engine}"
        end

        def default_cache_port(engine)
          {
            'redis' => 6379,
            'memcached' => 11211
          }[engine] or fail "no default port for engine #{engine}"
        end
      end # Class Methods
    end # AwsUtils
  end # Components::Aws
end # Podbay