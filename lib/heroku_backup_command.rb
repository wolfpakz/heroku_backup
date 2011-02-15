=begin
  Copyright (c) 2011 Dan Porter.

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

require 'heroku'
require 'heroku/command'

module Heroku::Command
  class Backup < BaseWithApp
    S3_KEY    = 'S3_KEY'
    S3_SECRET = 'S3_SECRET'

    def addons
      heroku.installed_addons(@app).select { |a| a['configured'] }
    end
    
    def bundles_addon_installed?
      addons.any? { |a| a['name'] =~ /bundles/ }
    end

    def config_file_path
      File.join(Dir.getwd, 'config', 's3.yml')
    end

    def download_backup
      file_name = download_file_name
      url       = latest_backup['public_url']
      File.open(file_name, "wb") { |f| f.write RestClient.get(url).to_s }
      display "Saved #{File.stat(file_name).size} byte backup to #{file_name}"
    end

    def download_file_name
      backup    = latest_backup
      created   = Time.parse(backup['finished_at'])
      created.strftime('%Y-%m-%d-%H%M') + ".dump"
    end

    # Capture a new bundle and back it up to S3.
    def index
      require 'erb'

      # Remove the deprecated bundles addon
      remove_bundles_addon if bundles_addon_installed?

      if missing_keys? && missing_config_file?
        display "ERROR: Set environment variables #{S3_KEY} and #{S3_SECRET}" +
                " or set up a config file at ./config/s3.yml to proceed." +
                "  \nSee README for more information."
        exit
      end
      
      if missing_pgbackups?
        display "===== Installing PG Backups Basic Addon..."
        heroku.install_addon(@app, "pgbackups:basic", {})
      end

      display "===== Capturing a new backup..."
      pgbackups.capture

      display "===== Downloading new bundle..."
      download_backup

      display "===== Pushing the bundle to S3..."
      if missing_keys?
        aws_creds =  YAML::load(ERB.new(File.read(config_file_path)).result)["production"]

        AWS::S3::Base.establish_connection!(
          :access_key_id     => aws_creds["access_key_id"],
          :secret_access_key => aws_creds["secret_access_key"]
        )
      else
        AWS::S3::Base.establish_connection!(
          :access_key_id     => ENV[S3_KEY],
          :secret_access_key => ENV[S3_SECRET]
        )
      end

      file_name = download_file_name
      AWS::S3::S3Object.store(s3_filename(file_name), open(file_name), s3_bucket)

      display "===== Deleting the temporary download file..."
      FileUtils.rm(file_name)
    end

    def latest_backup
      pgbackups.pgbackup_client.get_latest_backup
    end

    def missing_config_file?
      !File.exists? config_file_path
    end

    def missing_keys?
      ENV[S3_KEY].nil? || ENV[S3_SECRET].nil?
    end

    def missing_pgbackups?
      addons.find { |a| a['name'] =~ /pgbackups/ }.nil?
    end

    def pgbackups
      @pg ||= Heroku::Command::Pgbackups.new(['--app', @app, '--expire'])
    end

    def remove_bundles_addon
      addons.select { |a| a['name'] =~ /bundles/ }.each do |addon|
        display "==== Removing deprecated bundles addon #{addon['name']}"

        heroku.bundles(@app).each do |bundle|
          display "Removing bundle #{bundle[:name]}"
          heroku.bundle_destroy(@app, bundle[:name])
        end

        heroku.uninstall_addon(@app, addon['name'])
      end
    end

    def unlimited_bundles?
      !addons.find { |a| a['name'] =~ /bundles:unlimited/ }.nil?
    end

    private

    def s3_filename(backup_name)
      month_prefix = Time.parse(latest_backup["finished_at"]).strftime('%Y.%m')
      [month_prefix, backup_name].join('/')
    end

    def s3_bucket
      retries = 1
      begin
        return @app + '-backups' if AWS::S3::Bucket.find(@app + '-backups')
      rescue AWS::S3::NoSuchBucket
        AWS::S3::Bucket.create(@app + '-backups')
        retry if retries > 0 && (retries -= 1)
      end
    end

  end
end
