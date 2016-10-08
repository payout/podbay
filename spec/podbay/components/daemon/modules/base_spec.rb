require 'tempfile'
require 'fileutils'

module Podbay::Components
  class Daemon::Modules
    RSpec.describe Base do
      let(:base) { Base.new(daemon) }
      let(:daemon) { Daemon.new }

      describe '#signal_event' do
        let(:event_file) { Tempfile.new('test-event-file').path }
        subject { base.signal_event(event_name, event_file) }
        let(:event_file_contents) { subject; File.read(event_file) }
        after { FileUtils.rm(event_file) }

        context 'with event_name = "hello"' do
          let(:event_name) { 'hello' }

          it 'should write to file in expected format' do
            expect(event_file_contents).to eq "hello\n"
          end
        end # with event_name = "hello"

        context 'with another event already existing in file' do
          before { base.signal_event('previous_event', event_file) }
          let(:event_name) { 'new_event' }

          it 'should update file correctly' do
            expect(event_file_contents).to eq "previous_event\nnew_event\n"
          end
        end # with another event already existing in file

        context 'with same event already existing in file' do
          before { base.signal_event(event_name, event_file) }
          let(:event_name) { 'event' }

          it 'should not duplicate event in file' do
            expect(event_file_contents).to eq "event\n"
          end
        end # with same event already existing in file
      end # #signal_event

      describe '#event_signaled?' do
        let(:event_file) { Tempfile.new('test-event-file').path }
        subject { base.event_signaled?(event_name, event_file) }
        after { FileUtils.rm(event_file) }

        context 'with event file containing event' do
          before { 3.times { |i| base.signal_event("event#{i}", event_file) } }
          let(:event_name) { 'event2' }
          it { is_expected.to be true }
        end

        context 'with event file containing event and event passed as symbol' do
          before { 3.times { |i| base.signal_event("event#{i}", event_file) } }
          let(:event_name) { :event2 }
          it { is_expected.to be true }
        end

        context 'with event file empty' do
          let(:event_name) { 'event2' }
          it { is_expected.to be false }
        end

        context 'with event file not containing event' do
          before { 3.times { |i| base.signal_event("event#{i}", event_file) } }
          let(:event_name) { 'event4' }
          it { is_expected.to be false }
        end
      end # #event_signaled?
    end # Base
  end # Daemon::Modules
end # Podbay::Components
