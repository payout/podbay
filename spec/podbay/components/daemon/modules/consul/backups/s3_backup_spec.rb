module Podbay
  class Components::Daemon::Modules
    class Consul
      class Backups
        RSpec.describe S3Backup do
          let(:s3_backup) { S3Backup.new(uri) }
          let(:uri) { URI('s3://bucket-name/server/kv_backups') }

          let(:mock_secure_s3_file) { double('Podbay::Utils::SecureS3File') }
          let(:mock_s3_file) { double('Podbay::Utils::S3File') }

          around do |ex|
            Podbay::Utils::SecureS3File.mock(mock_secure_s3_file) do
              Podbay::Utils::S3File.mock(mock_s3_file) do
                ex.run
              end
            end
          end

          before do
            allow(mock_secure_s3_file).to receive(:new).with(
              's3://bucket-name/all/encryption_key'
            ).and_return(kms_key_file)

            allow(mock_s3_file).to receive(:new).with(
              's3://bucket-name/all/encryption_key'
            ).and_return(kms_key_file)
          end

          let(:kms_key_file) { double('kms_key_file', read: kms_key_id) }
          let(:kms_key_id) { '12345-1234' }

          describe '#new' do
            subject { S3Backup.new(uri) }

            it 'should set the bucket-name' do
              expect(subject.bucket).to eq 'bucket-name'
            end

            it 'should set the path' do
              expect(subject.path).to eq 'server/kv_backups'
            end

            context 'with kms_key_id' do
              let(:kms_key_id) { '12345-1234' }

              it 'should set the kms_key_id' do
                expect(subject.kms_key_id).to eq kms_key_id
              end
            end # with kms_key_id

            context 'without kms_key_id' do
              let(:kms_key_id) { nil }

              it 'should have a nil kms_key_id' do
                expect(subject.kms_key_id).to be nil
              end
            end # without kms_key_id
          end # #new

          describe '#backup' do
            subject { s3_backup.backup(data) }

            before do
              allow(mock_secure_s3_file).to receive(:new)
                .with(/s3:\/\/bucket-name\/server\/kv_backups\/\d{4}\/\d{14}.backup/)
                .and_return(s3_file)
              allow(mock_s3_file).to receive(:new)
                .with(/s3:\/\/bucket-name\/server\/kv_backups\/\d{4}\/\d{14}.backup/)
                .and_return(s3_file)
            end

            let(:data) do
              [
                {
                  key: "services/test",
                  value: '{"image":{"tag":"test-tag"}}'
                },
                {
                  key: "services/another-test",
                  value: '{"image":{"tag":"another-test-tag"}}'
                }
              ]
            end
            let(:s3_file) { double('S3File', write: nil, 'kms_key_id=' => nil) }
            let(:kms_key_id) { '12345-1234' }

            after { subject }

            context 'with kms_key_id' do
              let(:kms_key_id) { '12345-1234' }

              it 'should generate an S3 file path' do
                expect(mock_secure_s3_file).to receive(:new).with(
                  a_string_matching(
                    /s3:\/\/bucket-name\/server\/kv_backups\/\d{4}\/\d{14}.backup/
                  )
                )
              end

              it 'should set the kms key id' do
                expect(s3_file).to receive(:kms_key_id=).with(kms_key_id)
              end

              it 'should json-ify the data' do
                expect(s3_file).to receive(:write).with(data.to_json)
              end
            end # with kms_key_id

            context 'without kms_key_id' do
              let(:kms_key_id) { nil }

              it 'should write with just S3File' do
                expect(mock_s3_file).to receive(:new).with(
                  a_string_matching(
                    /s3:\/\/bucket-name\/server\/kv_backups\/\d{4}\/\d{14}.backup/
                  )
                )
              end

              it 'should json-ify the data' do
                expect(s3_file).to receive(:write).with(data.to_json)
              end
            end # without kms_key_id
          end # #backup

          describe '#shift_rolling_window', :shift_rolling_window do
            subject { s3_backup.shift_rolling_window(backup_window_size) }

            let(:backup_window_size) { 3 }
            let(:mock_s3_utils) { double('Podbay::Utils::S3') }
            let(:mock_utils) { double('Podbay::Utils') }

            around do |ex|
              Podbay::Utils::S3.mock(mock_s3_utils) do
                Podbay::Utils.mock(mock_utils) do
                  ex.run
                end
              end
            end

            before do
              allow(mock_utils).to receive(:current_time)
                .and_return(current_time)
              allow(mock_s3_utils).to receive(:bucket).and_return(bucket)

              allow(bucket).to receive(:objects) do |h|
                backups.select { |b| b.key.start_with?(h[:prefix]) }
              end
            end

            let(:current_time) { double('time', year: year) }
            let(:year) { 2016 }
            let(:bucket) { double('bucket') }
            let(:backups) { [] }

            after { subject }

            context 'with backup_window in this year' do
              context 'with no backup to delete' do
                let(:backups) do
                  3.times.each_with_index.map { |i|
                    double("2016/201601012#{i}0000.backup",
                      key: "server/kv_backups/2016/201601012#{i}0000.backup")
                  }
                end

                it 'should not delete any backups' do
                  backups.each { |b| expect(b).not_to receive(:delete) }
                end
              end # with no backup to delete

              context 'with backup to delete' do
                let(:backups) do
                  4.times.each_with_index.map { |i|
                    double("2016/201601012#{i}0000.backup",
                      key: "server/kv_backups/2016/201601012#{i}0000.backup")
                  }
                end

                before { allow(backups[0]).to receive(:delete) }

                it 'should delete the oldest backup' do
                  expect(backups[0]).to receive(:delete)
                end

                it 'should not delete the other backups' do
                  backups[1..3].each { |b| expect(b).not_to receive(:delete) }
                end
              end # with backup to delete

              context 'with last backup being only one of the day' do
                let(:backups) do
                  4.times.each_with_index.map { |i|
                    double("2016/2016010#{i + 1}000000.backup",
                      key: "server/kv_backups/2016/2016010#{i + 1}000000.backup")
                  }
                end

                it 'should not delete any backups' do
                  backups.each { |b| expect(b).not_to receive(:delete) }
                end
              end # with last backup being only one of the day
            end # with backup_window in this year

            context 'with backup_window across 2 years' do
              before { allow(backups[0]).to receive(:delete) }

              let(:backups) do
                [
                  double("2015/20151231210000.backup",
                    key: "server/kv_backups/2015/20151231210000.backup"),
                  double("2015/20151231220000.backup",
                    key: "server/kv_backups/2015/20151231220000.backup"),
                  double("2015/20151231230000.backup",
                    key: "server/kv_backups/2015/20151231230000.backup"),
                  double("2016/20160101000000.backup",
                    key: "server/kv_backups/2016/20160101000000.backup")
                ]
              end

              it 'should delete the oldest backup' do
                expect(backups[0]).to receive(:delete)
              end

              it 'should not delete the other backups' do
                backups[1..3].each { |b| expect(b).not_to receive(:delete) }
              end

              context 'with last backup being only one of the day' do
                let(:backups) do
                  [
                    double("2015/20151229230000.backup",
                      key: "server/kv_backups/2015/20151229230000.backup"),
                    double("2015/20151230230000.backup",
                      key: "server/kv_backups/2015/20151230230000.backup"),
                    double("2015/20151231230000.backup",
                      key: "server/kv_backups/2015/20151231230000.backup"),
                    double("2016/20160101000000.backup",
                      key: "server/kv_backups/2016/20160101000000.backup")
                  ]
                end

                it 'should not delete any backups' do
                  backups.each { |b| expect(b).not_to receive(:delete) }
                end
              end # with last backup being only one of the day

              context 'with not enough backups from last year' do
                let(:backups) do
                  [
                    double("2015/20151231230000.backup",
                      key: "server/kv_backups/2015/20151231230000.backup"),
                    double("2016/20160101000000.backup",
                      key: "server/kv_backups/2016/20160101000000.backup")
                  ]
                end

                it 'should not delete any backups' do
                  backups.each { |b| expect(b).not_to receive(:delete) }
                end
              end # with not enough backups from last year
            end # with backup_window across 2 years
          end # #shift_rolling_window

          describe '#retrieve' do
            subject { s3_backup.retrieve(time) }

            let(:time) { Time.parse('2016-01-01 23:59:59') }
            let(:mock_s3_utils) { double('Podbay::Utils::S3') }

            around do |ex|
              Podbay::Utils::S3.mock(mock_s3_utils) do
                ex.run
              end
            end

            before do
              allow(mock_s3_utils).to receive(:bucket).and_return(bucket)
              allow(bucket).to receive(:objects)
                .with(prefix: 'server/kv_backups').and_return(backups)

              allow(mock_secure_s3_file).to receive(:new)
                .with(/s3:\/\/bucket-name\/server\/kv_backups\/\d{4}\/\d{14}.backup/)
                .and_return(s3_file)
            end

            let(:backups) { [] }
            let(:bucket) { double('bucket') }
            let(:s3_file) { double('S3File', read: data) }
            let(:data) do
              [
                {
                  key: "services/test",
                  value: '{"image":{"tag":"test-tag"}}'
                },
                {
                  key: "services/another-test",
                  value: '{"image":{"tag":"another-test-tag"}}'
                }
              ].to_json
            end
            let(:backup_to_pick) do
              double('daily backup',
                key: 'server/kv_backups/2016/20160101230000.backup')
            end

            context 'with backup found' do
              let(:time) { Time.parse('2016-01-01 23:59:59') }
              let(:backups) do
                [
                  double(key: 'server/kv_backups/2016/20160101220000.backup'),
                  backup_to_pick,
                  double(key: 'server/kv_backups/2016/20160102000000.backup')
                ]
              end

              it 'should get retrieve the most recent backup based on time' do
                expect(mock_secure_s3_file).to receive(:new).with(
                  "s3://bucket-name/#{backup_to_pick.key}"
                )
                subject
              end

              it 'should return a result hash' do
                is_expected.to eq(
                  timestamp: '20160101230000',
                  data: JSON.parse(data, symbolize_names: true)
                )
              end
            end # with backup found

            context 'with no backup found' do
              let(:backups) { [] }
              it { is_expected.to be nil }
            end # with no backup found
          end # #retrieve
        end # S3Backup
      end # Backups
    end # Consul
  end # Components::Daemon::Modules
end # Podbay
