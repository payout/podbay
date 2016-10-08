require 'tmpdir'
require 'fileutils'

class Podbay::Components::Daemon
  RSpec.describe LoopDevices do
    let(:loop_devices) { LoopDevices.new(Dir.mktmpdir) }

    around do |ex|
      ex.run
      FileUtils.remove_dir(loop_devices.loop_path)
    end

    def expect_system(command)
      expect(loop_devices).to receive(
        :system).with(a_string_matching(command)).once
    end


    describe '#create_loop_dir', :create_loop_dir do
      let(:mounts_path_exists) { Dir.exist?(loop_devices.mounts_path) }
      let(:files_path_exists) { Dir.exist?(loop_devices.files_path) }
      let(:tabfile_exists) { File.exist?(loop_devices.tabfile_path) }
      let(:tabfile_contents) { File.read(loop_devices.tabfile_path) }

      subject { loop_devices.create_loop_dir }

      before do
        allow(loop_devices).to receive(:system)
      end

      it 'should create the mounts path' do
        subject
        expect(mounts_path_exists).to eq true
      end

      it 'should create the files path' do
        subject
        expect(files_path_exists).to eq true
      end

      it 'should create the tabfile if it does not exist' do
        subject
        expect(tabfile_exists).to eq true
      end

      it 'should not recreate the tabfile if it does already exist' do
        File.open(loop_devices.tabfile_path, 'w') { |file| file.write("test") }
        subject
        expect(tabfile_contents).to eq 'test'
      end
    end# create_loop_dir


    describe '#create', :create do
      let(:size_b) { 4194304 }
      let(:owner) { '4000' }
      let(:loop_device) { '/dev/loop0' }
      let(:tabfile_contents) { File.read(loop_devices.tabfile_path) }

      subject { loop_devices.create(size_b, owner) }

      before do
        allow(loop_devices).to receive(:system)

        allow(loop_devices).to receive(
          :`).with(a_string_matching(
            /losetup --show --sizelimit #{size_b} -f #{loop_devices.files_path}\/\h{8}/))
          .and_return(loop_device)
      end

      after { subject }

      it 'should create a loop device' do
        expect_system(
          /fallocate -l #{size_b} #{loop_devices.files_path}\/\h{8}/)
        expect(loop_devices).to receive(
          :`).with(a_string_matching(
            /losetup --show --sizelimit #{size_b} -f #{loop_devices.files_path}\/\h{8}/))
          .and_return(loop_device)
      end

      it 'should create a loop mount' do
        expect_system("mke2fs #{loop_device}")
        expect_system(/mkdir -p #{loop_devices.mounts_path}\/\h{8}/)
        expect_system(/mount -o nosuid,nodev,noexec #{loop_device} #{loop_devices.mounts_path}\/\h{8}/)
        expect_system(/chown -R #{owner}:#{owner} #{loop_devices.mounts_path}\/\h{8}/)
      end

      it 'should append to tab file' do
        subject
        expect(tabfile_contents).to match /\A\h{8}\t#{size_b}\t#{owner}\n\z/
      end


      it { is_expected.to match(/#{loop_devices.mounts_path}\/\h{8}/) }
    end # #create


    describe '#remove', :remove do
      subject { loop_devices.remove(mount_path) }

      let(:loop_name) { '01234567' }
      let(:size_b) { 4194304 }
      let(:owner) { '4000' }
      let(:tabfile_contents) { File.read(loop_devices.tabfile_path) }
      let(:mount_path) { "#{loop_devices.mounts_path}/#{loop_name}" }

      before do
        allow(loop_devices).to receive(:system)

        File.open(loop_devices.tabfile_path, 'a') do |file|
            file.write("#{loop_name}\t#{size_b}\t#{owner}\n")
        end
      end

      it 'should remove the only loop device' do
        subject
        expect(tabfile_contents).to eq ''
      end

      it 'should remove only one of two loop devices' do
        File.open(loop_devices.tabfile_path, 'a') do |file|
          file.write("12345678\t#{size_b}\t#{owner}\n")
        end

        subject
        expect(tabfile_contents).to eq "12345678\t#{size_b}\t#{owner}\n"
      end
    end # #remove

    describe '#resolve_tabfile', :resolve_tabfile do
      subject { loop_devices.resolve_tabfile }

      let(:loop_device) { '/dev/loop0' }
      let(:tabfile_contents) { File.read(loop_devices.tabfile_path) }
      let(:mount_path) { "#{loop_devices.mounts_path}/#{loop_name}" }

      before do
        allow(loop_devices).to receive(:system)

        allow(loop_devices).to receive(
          :`).with(a_string_matching(
            /losetup --show --sizelimit 4194304 -f #{loop_devices.files_path}\/\h{8}/))
          .and_return(loop_device)

        allow(loop_devices).to receive(:`).with(a_string_matching(/losetup -a/))
          .and_return('')

        File.open(loop_devices.tabfile_path, 'a') do |file|
            file.write("01234567\t4194304\t4000\n")
        end
      end

      after { subject }

      it 'should create based on entry in the tabfile' do
        expect_system("fallocate -l 4194304 #{loop_devices.files_path}/01234567")
        expect(loop_devices).to receive(
          :`).with(a_string_matching(
            /losetup --show --sizelimit 4194304 -f #{loop_devices.files_path}\/01234567/))
          .and_return(loop_device)

        expect_system("mke2fs #{loop_device}")
        expect_system(/mkdir -p #{loop_devices.mounts_path}\/01234567/)
        expect_system(/mount -o nosuid,nodev,noexec #{loop_device} #{loop_devices.mounts_path}\/01234567/)
        expect_system(/chown -R 4000:4000 #{loop_devices.mounts_path}\/01234567/)
      end

      it 'should not append to tabfile' do
        expect(tabfile_contents.scan(/01234567/).size).to eq 1
      end
    end # resolve_tabfile

    describe '#loop_devices', :loop_devices do
      subject { loop_devices }

      let(:loop_name) { '01234567' }
      let(:size_b) { 4194304 }
      let(:owner) { '4000' }

      before do
        File.open(loop_devices.tabfile_path, 'a') do |file|
            file.write("#{loop_name}\t#{size_b}\t#{owner}\n")
        end
      end

      it 'should return a hash of loop devices' do
        expect(loop_devices.loop_devices).to eq "01234567" => {
          :size => "4194304", :owner => "4000"
        }
      end
    end # loop_devices


    describe '#mount_paths_listing', :mount_paths_listing do
      subject { loop_devices.mount_paths_listing }

      let(:loop_name) { '01234567' }

      before do
        FileUtils::mkdir_p "#{loop_devices.mounts_path}/#{loop_name}"
      end

      it 'should return a mount path' do
        expect(subject).to eq ["#{loop_devices.mounts_path}/#{loop_name}"]
      end
    end # loop_devices

  end # Discoverer
end # Podbay::Components::Daemon
