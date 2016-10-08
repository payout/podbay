require 'docker-api'

module Podbay
  class Docker
    include Mixins::Mockable

    mockable :container, :event

    def stream_events(opts = {}, &block)
      _event.stream(opts, &block)
    end

    def inspect_container(container_id)
      json = `docker inspect #{container_id} 2> /dev/null`
      JSON.parse(json.force_encoding('UTF-8')).first
    end

    def containers
      _container.all.map(&:info)
    end

    def container_binds(container_id)
      inspect_container(container_id)['HostConfig']['Binds']
    end

    def stop(container_id)
      ::Docker.connection.post("/containers/#{container_id}/stop", 't' => 10)
    end

    def pull(name, tag)
      system("docker pull #{name}:#{tag}")
    end

    def load(path)
      system("docker load --input #{path}")
    end

    def ready?
      _container.all or fail 'received nil from _container.all'
      true
    rescue Excon::Errors::SocketError
      false
    end

    private

    def _container
      @_container ||= ::Docker::Container
    end

    def _event
      @_event ||= ::Docker::Event
    end
  end # Docker
end # Podbay
