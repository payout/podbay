require 'securerandom'

module Podbay
  RSpec.describe Consul do
    let(:consul) { Consul.new }

    describe '#register_service' do
      subject { consul.register_service(params) }
      let(:params) { { 'ID' => 'ex1', 'Name' => 'ex', 'Address' => '...' } }

      around { |ex| consul.mock_service(service_mock) { ex.run } }
      let(:service_mock) { double('service mock') }
      after { subject }

      it 'should call #register on service' do
        expect(service_mock).to receive(:register).with(params).once
      end
    end # #register_service

    describe '#get_service_definition', :get_service_definition do
      subject { consul.get_service_definition(service_name) }
      let(:service_name) { 'service_name' }

      around { |ex| Consul::Kv.mock(mock_kv) { ex.run } }

      before do
        allow(mock_kv).to receive(:get).and_return(defn)
      end

      let(:mock_kv) { double('mock Consul::Kv') }

      context 'with service defined' do
        let(:defn) { { name: 'service_name' } }
        it { is_expected.to eq(defn) }
      end

      context 'with service undefined' do
        let(:defn) { nil }
        it { is_expected.to eq({}) }
      end
    end # #get_service_definition

    describe '#get_service_check', :get_service_check do
      subject { consul.get_service_check(service_name) }
      let(:service_name) { 'service-name' }

      around { |ex| Consul::Kv.mock(mock_kv) { ex.run } }
      let(:mock_kv) { double('mock Consul::Kv') }

      before do
        allow(mock_kv).to receive(:get).with("services/#{service_name}")
          .and_return(check: check_data)
      end

      context 'with http check data' do
        let(:check_data) do
          { http: 'http://localhost:1234/check', interval: '10s' }
        end

        it 'should format keys properly' do
          is_expected.to eq(
            'HTTP' => 'http://localhost:1234/check',
            'Interval' => '10s'
          )
        end
      end

      context 'with tcp check data' do
        let(:check_data) do
          { tcp: 'localhost:1234', interval: '10s' }
        end

        it 'should format keys properly' do
          is_expected.to eq(
            'TCP' => 'localhost:1234',
            'Interval' => '10s'
          )
        end
      end

      context 'with ttl check data' do
        let(:check_data) do
          { ttl: '15s' }
        end

        it 'should format keys properly' do
          is_expected.to eq('TTL' => '15s')
        end
      end

      context 'with script check data' do
        let(:check_data) do
          { script: '/usr/local/bin/check.rb', interval: '20s' }
        end

        it 'should format keys properly' do
          is_expected.to eq(
            'Script' => '/usr/local/bin/check.rb',
            'Interval' => '20s'
          )
        end
      end

      context 'with interval with no second designation in check data' do
        let(:check_data) do
          { interval: '10' }
        end

        it 'should format interval value properly' do
          is_expected.to eq(
            'Interval' => '10s'
          )
        end
      end

      context 'with interval with a non-second designation in check data' do
        let(:check_data) do
          { interval: '1m' }
        end

        it 'should leave interval value alone' do
          is_expected.to eq(
            'Interval' => '1m'
          )
        end
      end

      context 'with invalid key in check data' do
        let(:check_data) do
          { invalid_key: 'value' }
        end

        it 'should remove invalid key' do
          is_expected.to eq({})
        end
      end

      context 'with no check defined' do
        let(:check_data) { nil }

        it 'should return empty hash' do
          is_expected.to eq({})
        end
      end
    end # #get_service_check

    describe '#node_healthy?' do
      subject do
        consul.node_healthy?(hostname, services_to_check, iterations)
      end

      let(:services_to_check) { [] }
      let(:iterations) { 2 }
      let(:health_mock) { double('health mock') }
      let(:service_checks) { [] }

      around { |ex| consul.mock_health(health_mock) { ex.run } }

      before do
        allow(health_mock).to receive(:node).with(hostname)
          .and_return(response)

        services_to_check.each_with_index do |service, i|
          allow(consul).to receive(:get_service_check).with(service)
            .and_return(service_checks[i])
        end
      end

      let(:response) do
        [
          {
            "Status" => "passing",
            "ServiceName" => "",
          }
        ]
      end
      let(:unhealthy_response) do
        [
          {
            "Status" => "critical",
            "ServiceName" => "",
          }
        ]
      end
      let(:hostname) { "ip-10-0-31-175" }

      context 'with healthy node' do
        it { is_expected.to be true }
      end

      context 'with unhealthy node' do
        before do
          allow(health_mock).to receive(:node).with(hostname)
            .and_return(unhealthy_response)
        end

        it { is_expected.to be false }

        context 'becoming healthy' do
          before do
            allow(health_mock).to receive(:node).with(hostname)
              .and_return(unhealthy_response, response)
          end

          it { is_expected.to be true }
        end
      end

      context 'with multiple nodes' do
        let(:response) do
          [
            {
              "Status" => "passing",
              "ServiceName" => "",
            },
            {
              "Status" => health,
              "ServiceName" => "",
            }
          ]
        end

        context 'with all nodes healthy' do
          let(:health) { "passing" }
          it { is_expected.to be true }
        end

        context 'with one node unhealthy' do
          let(:health) { "warning" }
          it { is_expected.to be false }
        end
      end

      context 'with services to check' do
        let(:services_to_check) { ['test-service'] }
        let(:service_checks) do
          [
            {
              'HTTP' => 'http://localhost:1234/check',
              'Interval' => '10s'
            }
          ]
        end
        let(:response) do
          [
            {
              "Status" => "passing",
              "ServiceName" => "",
            }
          ] + service_response
        end
        let(:service_response) do
          [{
            'Status' => service_health,
            'ServiceName' => service_name,
          }]
        end
        let(:service_health) { 'passing' }

        context 'with service present' do
          let(:service_name) { 'test-service' }
          let(:service_health) { 'passing' }

          context 'with services healthy' do
            let(:service_health) { 'passing' }
            it { is_expected.to be true }
          end

          context 'with services unhealthy' do
            let(:service_health) { 'critical' }
            it { is_expected.to be false }
          end

          context 'with no service check defined' do
            let(:service_response) { [] }
            let(:service_checks) { [{}] }

            it { is_expected.to be true }
          end
        end # with service present

        context 'without service present' do
          let(:service_name) { '' }
          it { is_expected.to be false }
        end

        context 'with multiple services' do
          let(:services_to_check) { ['test-service1', 'test-service2'] }
          let(:service_checks) do
            [
              {
                'HTTP' => 'http://localhost:1234/check',
                'Interval' => '10s'
              },
              {
                'HTTP' => 'http://localhost:1234/check',
                'Interval' => '10s'
              }
            ]
          end
          let(:service_response) do
            [
              {
                'Status' => 'passing',
                'ServiceName' => 'test-service1',
              },
              {
                'Status' => service_health,
                'ServiceName' => service_name,
              }
            ]
          end
          let(:service_name) { 'test-service2' }
          let(:service_health) { 'passing' }

          context 'with services present' do
            let(:service_name) { 'test-service2' }

            context 'with services healthy' do
              let(:service_health) { 'passing' }
              it { is_expected.to be true }
            end

            context 'with 1 service unhealthy' do
              let(:service_health) { 'critical' }
              it { is_expected.to be false }
            end

            context 'with no service checks defined' do
              let(:service_response) { [] }
              let(:service_checks) { [{}, {}] }

              it { is_expected.to be true }
            end

            context 'with 1 service check not defined' do
              let(:service_response) do
                [
                  {
                    'Status' => 'passing',
                    'ServiceName' => 'test-service1',
                  }
                ]
              end
              let(:service_checks) do
                [
                  {
                    'HTTP' => 'http://localhost:1234/check',
                    'Interval' => '10s'
                  }, {}
                ]
              end

              it { is_expected.to be true }
            end
          end # with services present

          context 'with 1 service not present' do
            let(:service_name) { '' }
            it { is_expected.to be false }
          end
        end # with multiple services
      end # with services to check
    end # #node_health?

    describe '#hostname_health_checks', :hostname_health_checks do
      subject { consul.hostname_health_checks(hostname, retries) }

      let(:hostname) { double('ip-10-0-0-10') }
      let(:mock_health) { double('Diplomat::Health') }
      let(:retries) { 5 }
      around { |ex| consul.mock_health(mock_health) { ex.run } }

      context 'with valid health checks existing' do
        before do
          allow(mock_health).to receive(:node).with(hostname)
            .and_return(node_checks)
        end

        let(:node_checks) do
          [
            {
              'Status' => 'passing',
              'ServiceName' => ''
            }
          ]
        end

        it { is_expected.to eq node_checks }
      end # with valid health checks existing

      context 'with health check request throwing an exception' do
        before do
          allow(mock_health).to receive(:node).with(hostname)
            .and_raise(Diplomat::PathNotFound.new)
          allow(consul).to receive(:sleep)
        end

        after { subject rescue nil }

        it 'should attempt retries + 1 times' do
          expect(mock_health).to receive(:node).exactly(retries + 1).times
        end

        it 'should raise the error' do
          expect { subject }.to raise_error Diplomat::PathNotFound
        end
      end # with health check request throwing an exception
    end # hostname_health_checks

    describe '#health_checks', :health_checks do
      subject { consul.health_checks }

      let(:mock_health) { double('Diplomat::Health') }
      around { |ex| consul.mock_health(mock_health) { ex.run } }

      before do
        allow(mock_health).to receive(:state).with('any')
          .and_return(states_resp)
      end

      let(:states_resp) { double('Diplomat::Health#state("any") response') }

      it 'should return response from Health.state("any")' do
        is_expected.to eq states_resp
      end
    end # #health_checks

    describe '#leader_ip' do
      subject { consul.leader_ip }

      before { allow(consul).to receive(:leader).and_return(leader_res) }

      let(:leader_res) { '1.2.3.4:8300' }

      it { is_expected.to eq '1.2.3.4' }
    end

    # service_healthy?
    describe '#service_healthy?', :service_healthy do
      subject { consul.service_healthy?(service, node) }
      let(:service) { 'my-service' }
      let(:node) { 'ip-10-0-0-10' }

      around do |ex|
        consul.mock_health(health_mock) do
          Consul::Kv.mock_store(mock_store) do
            ex.run
          end
        end
      end

      let(:health_mock) { double('health_mock mock') }
      let(:mock_store) { double('mock store') }

      before do
        allow(health_mock).to receive(:node).with(node)
          .and_return(node_checks)
        allow(mock_store).to receive(:get).with('services/my-service', {})
          .and_return(kv_response)
      end

      after { subject }

      context 'with a defined service check' do
        let(:node_checks) do
          [
            {
              'Status' => 'passing',
              'ServiceName' => ''
            },
            {
              'Status' => check_one_status,
              'ServiceName' => 'my-service'
            },
            {
              'Status' => check_two_status,
              'ServiceName' => 'my-service'
            }
          ]
        end
        let(:kv_response) do
          {
            :image => {
              :name => 'my-org/my-service'
            },
            :check => {
              :http => '/ping',
              :interval => '10s'
            }
          }
        end

        context 'with two of two services are healthy' do
          let(:check_one_status) { 'passing' }
          let(:check_two_status) { 'passing' }
          it { is_expected.to be true }
        end

        context 'with one of two services are healthy' do
          let(:check_one_status) { 'passing' }
          let(:check_two_status) { 'critical' }
          it { is_expected.to be false }
        end

        context 'with zero of two services are healthy' do
          let(:check_one_status) { 'critical' }
          let(:check_two_status) { 'critical' }
          it { is_expected.to be false }
        end

        context 'with health check not found' do
          let(:node_checks) do
            [
              {
                'Status' => 'passing',
                'ServiceName' => '',
              }
            ]
          end
          it { is_expected.to be false }
        end

        context 'with node checks not found' do
          let(:node_checks) { [] }
          it { is_expected.to be false }
        end
      end # with a defined service check

      context 'with no defined service check' do
        let(:node_checks) do
          [
            {
              'Status' => 'passing',
              'ServiceName' => ''
            }
          ]
        end
        let(:kv_response) do
          {
            :image => {
              :name => 'my-org/my-service'
            }
          }
        end
        it { is_expected.to be true }
      end # with no defined service check
    end # #service_healthy

    describe '#available_services', :available_services do
      subject { consul.available_services(index) }
      let(:index) { nil }
      let(:nindex) { 1 }
      let(:service_list) { ['consul', 'service_name'] }
      let(:get_all_responses) { [get_all_response(nindex, service_list)] }

      def get_all_response(ni, list)
        # Hash values don't matter
        [Hash[list.map {|k| [k, nil]}], ni]
      end

      around { |ex| consul.mock_service(service_mock) { ex.run } }
      let(:service_mock) { double('service mock') }

      before do
        allow(service_mock).to receive(:get_all).with(index: index)
          .and_return(*get_all_responses)
      end

      after { subject }

      it 'should call #get_all on service' do
        expect(service_mock).to receive(:get_all).with(index: index).once
      end

      it 'should return list of services minus consul and new index' do
        is_expected.to eq [service_list - ['consul'], nindex]
      end

      context 'with ModifyIndex returned as the previous index once' do
        let(:index) { 1 }
        let(:nindex) { 2 }

        let(:get_all_responses) do
          [
            get_all_response(index, service_list),
            get_all_response(nindex, service_list)
          ]
        end

        it 'should return list of services minus consul and new index' do
          is_expected.to eq [service_list - ['consul'], nindex]
        end
      end

      context 'with #get_all raising timeout error and then returning result' do
        before do
          calls = 0

          allow(service_mock).to receive(:get_all) do
            fail Diplomat::Timeout if (calls += 1) == 1
            get_all_response(1, service_list)
          end
        end

        it 'should handle timeout gracefully and make second request' do
          is_expected.to eq [service_list - ['consul'], 1]
        end
      end
    end # #available_services

    describe '#service_addresses', :service_addresses do
      subject { consul.service_addresses(service_name, index) }

      before do
        allow(consul).to receive(:service_addresses!).with(service_name, index)
          .and_return(*service_addresses_responses)
      end

      let(:service_name) { 'service-name' }
      let(:index) { nil }
      let(:service_addresses_responses) { [[addresses, nindex]] }
      let(:addresses) { double('addresses') }
      let(:nindex) { 1 }

      after { subject }

      it 'should return expected response' do
        is_expected.to eq [addresses, nindex]
      end

      context 'with service_addresses! returning nil first' do
        let(:service_addresses_responses) { [nil, [addresses, nindex]] }

        it 'should return expected response' do
          is_expected.to eq [addresses, nindex]
        end
      end
    end # #service_addresses

    describe '#service_addresses!', :service_addresses! do
      subject { consul.service_addresses!(service_name, index) }
      let(:get_resp) { [resp_address(service_id, ip, port)] }
      let(:service_name) { 'service_name' }
      let(:service_id) { "#{service_name}-1234" }
      let(:ip) { '10.0.0.10' }
      let(:node) { 'ip-10-0-0-10' }
      let(:port) { 3001 }
      let(:addresses) do
        get_resp.map do |r|
          { id: r.ServiceID, ip: r.ServiceAddress, port: r.ServicePort,
            node: r.Node }
        end
      end

      def resp_address(id, ip, port)
        double('resp address', ServiceID: id, ServiceAddress: ip,
          ServicePort: port, Node: node)
      end

      around { |ex| consul.mock_service(service_mock) { ex.run } }
      let(:service_mock) { double('service mock') }

      before do
        allow(service_mock).to receive(:get).with(service_name, :all,
          {index: index, wait: '2s'}, {}) do |name, _, _, meta|
          meta[:index] = meta_index
          get_resp
        end
      end

      after { subject }

      context 'with meta index is different from the original index' do
        let(:index) { nil }
        let(:meta_index) { 1 }

        it 'should call #get on service' do
          expect(service_mock).to receive(:get).with(service_name, :all,
            {index: index, wait: '2s'}, {}).once
        end

        it 'should return expect response' do
          is_expected.to eq [addresses, meta_index]
        end
      end

      context 'with meta index is the same as the original index' do
        let(:index) { 1 }
        let(:meta_index) { 1 }

        it 'should call #get on service' do
          expect(service_mock).to receive(:get).with(service_name, :all,
            {index: index, wait: '2s'}, {}).once
        end

        it 'should return nil' do
          is_expected.to be nil
        end
      end
    end # #service_addresses!

    describe '#service_nodes', :service_nodes do
      subject { consul.service_nodes(service_name) }
      let(:service_name) { 'service-name' }
      let(:resp_service_addresses!) { [{node: 'ip-10-0-0-10'}] }

      before do
        allow(consul).to receive(:service_addresses!).with(service_name)
          .and_return([resp_service_addresses!])
      end

      after { subject }

      it 'should call #service_addresses!' do
        expect(consul).to receive(:service_addresses!).with(service_name).once
      end

      context 'with one node returned' do
        it 'should return nodes' do
          is_expected.to eq ['ip-10-0-0-10']
        end
      end

      context 'with two nodes returned' do
        let(:resp_service_addresses!) { [{node: 'one'}, {node: 'two'}] }

        it 'should return nodes' do
          is_expected.to eq ['one', 'two']
        end
      end
    end # #service_nodes

    describe '#service', :service do
      subject { Consul.service(service_name) }
      let(:service_name) { 'service-name' }
      it { is_expected.to be_a Consul::Service }
      it { is_expected.to have_attributes(name: service_name.to_sym) }
    end # #service

    describe '#ready?', :ready? do
      subject { consul.ready? }

      around { |ex| consul.mock_status(status_mock) { ex.run } }
      let(:status_mock) { double('status mock') }

      context 'with #leader returning ""' do
        before { allow(status_mock).to receive(:leader).and_return '""' }
        it { is_expected.to be false }
      end

      context 'with #leader returning "10.0.0.10:1234"' do
        before do
          allow(status_mock).to receive(:leader).and_return '"10.0.0.10:1234"'
        end

        it { is_expected.to be true }
      end

      context 'with #leader raising Faraday::ConnectionFailed' do
        before do
          allow(status_mock).to receive(:leader)
            .and_raise(Faraday::ConnectionFailed.new('failed'))
        end

        it { is_expected.to be false }
      end
    end # #ready?

    describe '#handle_events', :handle_events do
      subject { consul.handle_events(*event_names, &event_block) }
      let(:event_block) { proc {} }

      before do
        allow(consul).to receive(:events).and_return([initial_events, index])
        allow(consul).to receive(:loop).and_yield
        allow(consul).to receive(:events).with(index: index)
          .and_return([new_events, new_index])
        allow(event_block).to receive(:call)
      end

      after { subject }

      def gen_event(name)
        { 'ID' => SecureRandom.uuid, 'Name' => name }
      end

      let(:index) { '1' }
      let(:new_index) { index.next }

      context 'when listening for "event1"' do
        let(:event_names) { ['event1'] }

        context 'with no initial events' do
          let(:initial_events) { [] }

          context 'with one new event1' do
            let(:new_events) { [gen_event('event1')] }

            it 'should call event block once' do
              expect(event_block).to receive(:call).once
            end

            it 'should call event block with new event1' do
              expect(event_block).to receive(:call).with(new_events.first).once
            end
          end # with one new event1

          context 'with two new event1' do
            let(:new_events) { [gen_event('event1'), gen_event('event1')] }

            it 'should call event block twice' do
              expect(event_block).to receive(:call).twice
            end

            it 'should pass first event to event block' do
              expect(event_block).to receive(:call).with(new_events.first).once
            end

            it 'should pass second event to event block' do
              expect(event_block).to receive(:call).with(new_events.second).once
            end
          end # with one new event1

          context 'with one new event2' do
            let(:new_events) { [gen_event('event2')] }

            it 'should not call event block once' do
              expect(event_block).not_to receive(:call)
            end
          end # with one new event2
        end # with no initial events

        context 'with an initial old event1' do
          let(:initial_events) { [gen_event('event1')] }

          context 'with one new event1' do
            let(:new_events) { [gen_event('event1')] }

            it 'should call event block once' do
              expect(event_block).to receive(:call).once
            end

            it 'should call event block with new event1' do
              expect(event_block).to receive(:call).with(new_events.first).once
            end
          end # with one new event1

          context 'with two new event1' do
            let(:new_events) { [gen_event('event1'), gen_event('event1')] }

            it 'should call event block twice' do
              expect(event_block).to receive(:call).twice
            end

            it 'should pass first event to event block' do
              expect(event_block).to receive(:call).with(new_events.first).once
            end

            it 'should pass second event to event block' do
              expect(event_block).to receive(:call).with(new_events.second).once
            end
          end # with one new event1
        end # with an initial old event1
      end # when listening for "event1"

      context 'when listening for "event1" and "event2"' do
        let(:event_names) { ['event1', 'event2'] }

        context 'with no initial events' do
          let(:initial_events) { [] }

          context 'with one new event1' do
            let(:new_events) { [gen_event('event1')] }

            it 'should call event block once' do
              expect(event_block).to receive(:call).once
            end

            it 'should call event block with new event1' do
              expect(event_block).to receive(:call).with(new_events.first).once
            end
          end # with one new event1

          context 'with two new event1' do
            let(:new_events) { [gen_event('event1'), gen_event('event1')] }

            it 'should call event block twice' do
              expect(event_block).to receive(:call).twice
            end

            it 'should pass first event to event block' do
              expect(event_block).to receive(:call).with(new_events.first).once
            end

            it 'should pass second event to event block' do
              expect(event_block).to receive(:call).with(new_events.second).once
            end
          end # with one new event1

          context 'with one new event2' do
            let(:new_events) { [gen_event('event2')] }

            it 'should call event block once' do
              expect(event_block).to receive(:call).once
            end

            it 'should call event block with new event1' do
              expect(event_block).to receive(:call).with(new_events.first).once
            end
          end # with one new event2

          context 'with one new event1 and one new event2' do
            let(:new_events) { [gen_event('event1'), gen_event('event2')] }

            it 'should call event block twice' do
              expect(event_block).to receive(:call).twice
            end

            it 'should pass first event to event block' do
              expect(event_block).to receive(:call).with(new_events.first).once
            end

            it 'should pass second event to event block' do
              expect(event_block).to receive(:call).with(new_events.second).once
            end
          end # with one new event1
        end # with no initial events
      end # when listening for "event1" and "event2"
    end # #handle_events

    describe '#open_action_channel' do
      subject { consul.open_action_channel(channel_name) }

      let(:channel_name) { 'test-channel' }

      it { is_expected.to be_a Podbay::Consul::ActionChannel }
      it { is_expected.to have_attributes(name: channel_name.to_sym) }
    end # #open_action_channel

    describe '#begin_action' do
      subject { consul.begin_action(action_name, params) }

      let(:action_name) { 'action-name' }
      let(:params) { { ttl: 30 } }

      before do
        allow(consul).to receive(:open_action_channel)
          .and_return(action_channel)
      end

      after { subject }

      let(:action_channel) { double('action channel', begin_action: action) }
      let(:action) { double('action') }

      it 'should open a channel called consul' do
        expect(consul).to receive(:open_action_channel).with('consul')
      end

      it 'should begin the action' do
        expect(action_channel).to receive(:begin_action).with(action_name,
          params)
      end
    end # #begin_action
  end # Consul
end # Podbay::Components::Daemon
