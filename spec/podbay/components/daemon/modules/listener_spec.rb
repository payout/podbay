module Podbay::Components
  class Daemon::Modules
    RSpec.describe Listener do
      let(:daemon) { Daemon.new }
      let(:listener) { Listener.new(daemon) }
      let(:servlet) { Listener::Servlet.new(server) }
      let(:server) { @server }

      before(:all) { @server = WEBrick::HTTPServer.new(Port: Podbay::SERVER_INFO_PORT) }
      after(:all) { @server.shutdown }

      describe 'Servlet' do
        describe '#do_GET' do
          subject { servlet.do_GET(request, response) }

          let(:request) { double('request') }
          let(:response) { double('response') }
          let(:status) { double('status') }
          let(:body) { double('body') }

          before do
            allow(request).to receive(:path).and_return(path)
            allow(response).to receive(:status=)
            allow(response).to receive(:body=)
          end

          after { subject }

          context 'with /consul_info' do
            let(:path) { '/consul_info' }
            let(:info) do
              %{
raft:
  applied_index = a
  commit_index = 184990
  fsm_pending = 0
  last_contact = 31.525326ms
  last_log_index = 184990
  last_log_term = 1188
  last_snapshot_index = 180712
  last_snapshot_term = 1145
              }
            end

            before do
              allow(servlet).to receive(:`).with('consul info').and_return(info)
            end

            it 'should respond with 200' do
              expect(response).to receive(:status=).with(200)
            end

            it 'should respond with the consul info' do
              expect(response).to receive(:body=).with(
                "{\"raft\":{\"applied_index\":\"a\",\"commit_index\":184990" \
                ",\"fsm_pending\":0,\"last_contact\":\"31.525326ms\",\"" \
                "last_log_index\":184990,\"last_log_term\":1188,\"" \
                "last_snapshot_index\":180712,\"last_snapshot_term\":1145}}"
              )
            end
          end # with /consul_info

          context 'with /invalid_path' do
            let(:path) { '/invalid_path' }

            it 'should respond with 404' do
              expect(response).to receive(:status=).with(404)
            end
          end
        end # #do_GET
      end # Servlet
    end # Listener
  end # Daemon:Modules
end # Podbay::Components
