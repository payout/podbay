module Podbay
  class Components::Aws
    module Validation
      class << self
        def validate_bootstrap_params(params)
          accepted_params = [:ami, :role, :dmz, :size, :instance_type,
            :discovery_mode, :elb, :key_pair, :modules].freeze
          required_params = [:ami, :role].freeze

          _validate_accepted_params(accepted_params, params)
          _validate_required_params(required_params, params)

          if params[:role] == 'server'
            unless params[:size]
              fail ValidationError, "param 'size' is required for role=server"
            end
          end

          _validate_role(params[:role])
          _validate_modules(params[:modules]) if params[:modules]
          _validate_dmz(params)
        end

        def validate_teardown_params(group_name, params)
          unless group_name.match(/\Agr-[A-Za-z0-9]+\z/)
            fail ValidationError, "invalid group name: #{group_name.inspect}"
          end
          _validate_accepted_params([], params)
        end

        def validate_deploy_params(params)
          accepted_params = [:ami, :group, :instance_type].freeze
          required_params = [:group].freeze

          _validate_accepted_params(accepted_params, params)
          _validate_required_params(required_params, params)
        end

        def validate_upgrade_params(params)
          accepted_params = [:ami].freeze
          required_params = [:ami].freeze

          _validate_accepted_params(accepted_params, params)
          _validate_required_params(required_params, params)
        end

        def validate_db_setup_params(params)
          accepted_params = [:engine, :allocated_storage, :instance_class,
            :username, :password, :maintenance_window, :backup_retention_period,
            :multi_az, :engine_version, :license_model, :group,
            :backup_window].freeze
          required_params = [:engine, :allocated_storage, :engine_version,
            :license_model, :maintenance_window, :username, :password,
            :group, :backup_window].freeze

          _validate_accepted_params(accepted_params, params)
          _validate_required_params(required_params, params)

          _validate_db_engine(params[:engine], params[:engine_version])
        end

        def validate_cache_setup_params(params)
          accepted_params = [:engine, :engine_version, :cache_node_type,
            :snapshot_retention_limit, :snapshot_window, :group]
          required_params = [:engine, :engine_version, :snapshot_window, :group]

          _validate_accepted_params(accepted_params, params)
          _validate_required_params(required_params, params)

          _validate_cache_engine(params[:engine], params[:engine_version])
        end

        def _validate_accepted_params(accepted, params)
          unless (invalid_params = params.keys - accepted).empty?
            fail ValidationError, "invalid params: #{invalid_params.join(', ')}"
          end
        end

        def _validate_required_params(required, params)
          unless (missing = required - params.keys).empty?
            fail ValidationError, "missing params: #{missing.join(', ')}"
          end
        end

        def _validate_modules(modules)
          accepted_params = [:static_services, :registrar].freeze
          _validate_accepted_params(accepted_params, modules)

          if (ss = modules[:static_services]) && !ss.is_a?(Array)
            fail ValidationError, 'modules.static_services[] must be an array'
          end

          if (r = modules[:registrar]) && !['on', 'off'].include?(r)
            fail ValidationError, 'modules.registrar must be either "on" or ' \
              '"off"'
          end
        end

        def _validate_db_engine(engine, version)
          unless ['postgres'].include?(engine)
            fail ValidationError, "invalid db engine #{engine.inspect}"
          end

          unless Resources::RDS.db_engine_versions(engine: engine)
            .map(&:version).include?(version)
            fail ValidationError, "invalid db engine version #{version.inspect}"
          end
        end

        def _validate_cache_engine(engine, version)
          unless ['redis'].include?(engine)
            fail ValidationError, "invalid cache engine #{engine.inspect}"
          end

          versions = Resources::ElastiCache.describe_cache_engine_versions(
            engine: engine).cache_engine_versions.map(&:engine_version)

          unless versions.include?(version)
            fail ValidationError, "invalid cache engine version " \
              "#{version.inspect}"
          end
        end

        def _validate_role(role)
          unless ['client', 'server'].include?(role)
            fail ValidationError, "invalid role value #{role.inspect}"
          end
        end

        def _validate_dmz(params)
          unless ['true', 'false'].include?(params[:dmz] ||= 'false')
            fail ValidationError, "invalid dmz value #{params[:dmz].inspect}"
          end

          if params[:dmz] == 'true'
            if params[:role] == 'server'
              fail ValidationError, 'server cannot be deployed in the DMZ'
            end

            # Validate elb params if they are present
            _validate_elb(params[:elb]) if params[:elb]
          else
            if params[:elb]
              fail ValidationError, 'ELB currently only supported in DMZ'
            end
          end
        end

        def _validate_elb(elb)
          required_elb_params = [:ssl_certificate_arn].freeze
          unless (missing = required_elb_params - elb.keys).empty?
            fail ValidationError, "missing ELB params: #{missing.join(', ')}"
          end
        end
      end # Class Methods
    end # Validation
  end # Components::Aws
end # Podbay
