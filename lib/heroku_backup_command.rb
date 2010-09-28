=begin
  Copyright (c) 2010 Matt Buck.

  This file is part of Heroku Backup Command.

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

module Heroku::Command
  class Backup < BaseWithApp
    S3_KEY    = 'S3_KEY'
    S3_SECRET = 'S3_SECRET'

    def app_option
      '--app ' + @app
    end

    def latest_bundle_name
      %x{ heroku bundles #{app_option} | cut -f 1 -d ' ' | sed '$!d' }.chomp
    end
    
    def perma_bundle_name
      [latest_bundle_name, [name, Time.now.strftime('%H%M')].join('-')
    end
    
    def unlimited_bundles?
      bundle_addon = %x{ heroku addons #{app_option} | grep bundles }
      bundle_addon =~ /unlimited/
    end
    
    def missing_bundles_addon?
      bundle_addon = %x{ heroku addons #{app_option} | grep bundles }
      bundle_addon == ''
    end

    # Capture a new bundle and back it up to S3.
    def index
      require 'erb'

      if missing_keys? && missing_config_file?
        display "ERROR: Set environment variables #{S3_KEY} and #{S3_SECRET}" +
                " or set up a config file at ./config/s3.yml to proceed." +
                "  \nSee README for more information."
        exit
      end
      
      if missing_bundles_addon?
        display "===== Installing Single Bundle Addon..."
        %x{ heroku addons:add bundles:single #{app_option} }
      end

      unless unlimited_bundles?
        display "===== Deleting most recent bundle from Heroku..."

        %x{ heroku bundles:destroy #{latest_bundle_name} #{app_option} }
      end

      display "===== Capturing a new bundle..."

      %x{ heroku bundles:capture #{app_option} }

      while %x{ heroku bundles #{app_option} | grep '#{latest_bundle_name}' } =~ /capturing/
        sleep 10
      end

      display "===== Downloading new bundle..."

      %x{ heroku bundles:download #{app_option} }

      display "===== Pushing the bundle up to S3..."

      # Establish a connection to S3.

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

      bundle_file_name = @app + '.tar.gz'

      AWS::S3::S3Object.store(s3_filename(perma_bundle_name), open(bundle_file_name), s3_bucket)

      display "===== Deleting the temporary bundle file..."

      FileUtils.rm(bundle_file_name)
    end

    private

      def config_file_path
        File.join(Dir.getwd, 'config', 's3.yml')
      end
      
      def s3_filename(bundle_name)
        month_prefix = Date.today.strftime('%Y.%m')
        filename = bundle_name + '.tar.gz'
        [month_prefix, filename].join('/')
      end

      def missing_config_file?
        !File.exists? config_file_path
      end

      def missing_keys?
        ENV[S3_KEY].nil? || ENV[S3_SECRET].nil?
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
