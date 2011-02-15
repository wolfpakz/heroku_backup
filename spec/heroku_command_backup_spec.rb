require './spec_helper'
require '../lib/heroku_backup_command'

describe Heroku::Command::Backup do
  before(:each) do
    @app = "test-app"
    @backup = Heroku::Command::Backup.new(['--app', @app])
  end

  describe "bundles_addon_installed?" do
    it "should return true if bundles:single is installed" do
      addons = [{"name"=>"bundles:single", "description"=>"Single Bundle", "configured"=>true}]
      @backup.expects(:addons).returns(addons)
      @backup.bundles_addon_installed?.should be_true
    end

    it "should return true if bundles:unlimited is installed" do
      addons = [{"name"=>"bundles:unlimited", "description"=>"Unlimited Bundles", "configured"=>true}]
      @backup.expects(:addons).returns(addons)
      @backup.bundles_addon_installed?.should be_true
    end

    it "should return false if no bundles addons are installed" do
      addons = [{"name"=>"redis:basic", "description"=>"Redis", "configured"=>true}]
      @backup.expects(:addons).returns(addons)
      @backup.bundles_addon_installed?.should be_false
    end
  end

  describe "missing_keys?" do
    #ENV[S3_KEY].nil? || ENV[S3_SECRET].nil?
    it "should return true if S3_KEY is not set" do
      ENV.delete(Heroku::Command::Backup::S3_KEY)
      @backup.missing_keys?.should be_true
    end

    it "should return true if S3_SECRET is not set" do
      ENV.delete(Heroku::Command::Backup::S3_SECRET)
      @backup.missing_keys?.should be_true
    end

    it "should return false if S3_KEY and S3_SECRET are set" do
      ENV[Heroku::Command::Backup::S3_KEY]    = 'mykey'
      ENV[Heroku::Command::Backup::S3_SECRET] = 'mysecret'
      @backup.missing_keys?.should be_false
    end
  end

  describe "missing_pgbackups?" do
    it "should return true if no pgbackups addons are installed" do
      addons = [{"name"=>"redis:basic", "description"=>"Redis", "configured"=>true}]
      @backup.expects(:addons).returns(addons)
      @backup.missing_pgbackups?.should be_true
    end

    it "should return false if pgbackups:basic is installed" do
      addons = [{"name"=>"pgbackups:basic", "description"=>"PG Backups Basic", "configured"=>true}]
      @backup.expects(:addons).returns(addons)
      @backup.missing_pgbackups?.should be_false
    end

    it "should return false if pgbackups:plus is installed" do
      addons = [{"name"=>"pgbackups:plus", "description"=>"PG Backups Plus", "configured"=>true}]
      @backup.expects(:addons).returns(addons)
      @backup.missing_pgbackups?.should be_false
    end
  end

end