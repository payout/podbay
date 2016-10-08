module Podbay
  class Components::Daemon::Modules
    class Consul
      class Backups
        class S3Backup < Backup
          attr_reader :bucket
          attr_reader :path
          attr_reader :kms_key_id

          def initialize(uri)
            @bucket = uri.host
            @path = uri.path.split('/').reject(&:empty?).join('/')
            @kms_key_id = _retrieve_kms_key
          end

          def backup(data)
            timestamp = Utils.timestamp(Time.now)
            year = timestamp[0..3]
            file_name = timestamp + '.backup'
            file_path = "#{year}/#{file_name}"

            # Write file to path /year/file_name.backup
            if kms_key_id
              Utils::SecureS3File.write(
                _backup_file_path(file_path),
                data.to_json,
                kms_key_id
              )
            else
              Utils::S3File.write(_backup_file_path(file_path), data.to_json)
            end
          end

          def shift_rolling_window(backup_window_size = BACKUP_WINDOW_SIZE)
            this_year = Utils.current_time.year
            backups = _backups_from(this_year)

            # Get last years backups if there aren't enough this year
            num_backups_to_get = backup_window_size + 1
            if backups.size < num_backups_to_get
              backups = _backups_from(this_year - 1) + backups
            end

            return if backups.size < num_backups_to_get

            # Get the most recent backups
            backups = backups[-num_backups_to_get, num_backups_to_get]

            # Delete the last backup in the window if it's the only backup
            # from its day
            backup_to_shift = backups.first
            backup_to_shift.delete unless _only_backup_of_day?(backup_to_shift)
          end

          def retrieve(time = Time.now)
            time = Utils.timestamp(time)
            backups = Utils::S3.bucket(bucket).objects(prefix: path).to_a

            # Get the most recent backup based on param 'time'. Retrieve the
            # timestamps out of the filenames
            # [server/kv_backups/2016/20160826120000.backup]
            #   => [20160826120000]
            file_timestamp = backups
              .map { |b| b.key.split('/').last[0..-8] }
              .reject { |fn| fn > time }
              .sort_by { |fn| fn }
              .last

            if file_timestamp
              restore_filename = file_timestamp.slice(0..3) + '/' +
                file_timestamp + '.backup'

              {
                timestamp: file_timestamp,
                data: JSON.parse(
                  Utils::SecureS3File.read(_backup_file_path(restore_filename)),
                  symbolize_names: true
                )
              }
            end
          end

          private

          def _backup_file_path(file_path)
            "s3://#{bucket}/#{path}/#{file_path}"
          end

          def _backups_from(year)
            _backups_with_prefix(path + '/' + year.to_s + '/')
          end

          def _only_backup_of_day?(backup)
            # server/kv_backups/2016/20160826120000.backup
            #   => server/kv_backups/2016/20160826
            prefix = backup.key[0..-14]
            _backups_with_prefix(prefix).count == 1
          end

          def _backups_with_prefix(prefix)
            Utils::S3.bucket(bucket).objects(prefix: prefix).to_a
          end

          def _retrieve_kms_key
            Utils::S3File.read("s3://#{bucket}/all/encryption_key")
          end
        end # S3Backup
      end # Backups
    end # Consul
  end # Components::Daemon::Modules
end # Podbay
