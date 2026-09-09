require "json"
require "ostruct"
$LOADED_FEATURES.concat(["pilot.rb", "pilot/options.rb"])
$events = []
$scenario = ENV.fetch("APPSTORE_SCENARIO", "new")
$notes = "Fixed playback"

module FastlaneCore
  module UI
    def self.user_error!(message); raise message; end
    def self.message(message); $events << ["message", message]; end
    def self.success(message); $events << ["success", message]; end
  end
end

class FakeLocalization
  attr_accessor :whats_new
  attr_reader :description
  def initialize(notes)
    @whats_new = notes
    @description = "Existing description and screenshots"
  end
  def update(attributes:)
    raise "Unexpected metadata edit" unless attributes.keys == [:whatsNew]
    $events << ["write_notes", attributes]
    @whats_new = attributes[:whatsNew] unless $scenario == "notes_not_saved"
  end
end

class FakeVersion
  attr_accessor :id, :version_string, :app_version_state, :release_type, :build, :localizations
  def initialize(id, number, state)
    @id, @version_string, @app_version_state = id, number, state
    @release_type = "AFTER_APPROVAL"
    @localizations = [FakeLocalization.new("Old notes"), FakeLocalization.new("Old notes")]
  end
  def get_app_store_version_localizations
    localizations
  end
  def update(attributes:)
    raise "Unexpected version edit" unless attributes.keys == [:releaseType]
    $events << ["write_release_type", attributes]
    @release_type = attributes[:releaseType] unless $scenario == "release_not_saved"
  end
  def select_build(build_id:)
    $events << ["write_build", build_id]
    @build = $builds.find { |candidate| candidate.id == build_id } unless $scenario == "build_not_saved"
  end
end

class FakeReview
  attr_accessor :id, :state, :items
  def initialize
    @id, @state, @items = "review-id", "READY_FOR_REVIEW", []
  end
  def add_app_store_version_to_review_items(app_store_version_id:)
    $events << ["write_review_item", app_store_version_id]
    @items = [OpenStruct.new(app_store_version: $target)]
    $target.app_version_state = "READY_FOR_REVIEW"
  end
  def submit_for_review
    $events << ["write_submit"]
    unless $scenario == "unconfirmed"
      @state = "WAITING_FOR_REVIEW"
      $target.app_version_state = "WAITING_FOR_REVIEW"
    end
    if $scenario == "response_lost" && !$lost
      $lost = true
      raise "Submission response lost"
    end
  end
end

class FakeApp
  def id; "app-id"; end
  def get_app_store_versions(**options)
    $events << ["versions", options]
    $versions
  end
  def get_review_submissions(**options)
    $events << ["reviews", options]
    $reviews
  end
  def create_review_submission(platform:)
    $events << ["write_create_review", platform]
    review = FakeReview.new
    $reviews << review
    review
  end
end

module FastlaneCore
  class Configuration
    def self.create(_options, values); values; end
  end
end
module Pilot
  class Options
    def self.available_options; []; end
  end
  class BuildManager
    def start(config); $events << ["login", config]; end
    def app; FakeApp.new; end
  end
end
module Spaceship
  class ConnectAPI
    class << self
      attr_accessor :token
      def get_build(build_id:)
        $events << ["audience", build_id]
        audience = $scenario == "internal_only" ? "INTERNAL_ONLY" : "APP_STORE_ELIGIBLE"
        OpenStruct.new(body: { "data" => { "attributes" => { "buildAudienceType" => audience } } })
      end
      def post_app_store_version(app_id:, attributes:)
        $events << ["write_create_version", app_id, attributes]
        $target = FakeVersion.new("target-id", attributes[:versionString], "PREPARE_FOR_SUBMISSION")
        $versions << $target
        [$target]
      end
    end
    class Token
      def self.create(**options); $events << ["token", options]; :token; end
    end
    class Build
      def self.all(**options)
        $events << ["builds", options]
        options[:build_number] ? $builds.select { |build| build.version == options[:build_number] } : $builds
      end
    end
    class AppStoreVersion
      def self.get(app_store_version_id:, **options)
        $events << ["readback", app_store_version_id, options]
        $versions.find { |version| version.id == app_store_version_id }
      end
    end
    class ReviewSubmissionItem
      def self.all(review_submission_id:, includes:)
        $events << ["items", review_submission_id, includes]
        $reviews.find { |review| review.id == review_submission_id }.items
      end
    end
  end
end

def make_build(number, state = "VALID")
  OpenStruct.new(id: "build-#{number}", version: number, app_version: "1.0.1", platform: "IOS", app_id: "app-id",
                 processing_state: state, expired: false, uses_non_exempt_encryption: false, missing_export_compliance?: false)
end
$builds = [make_build("570", "PROCESSING"), make_build("569"), make_build("568")]
$versions = [FakeVersion.new("live-id", "1.0", "READY_FOR_DISTRIBUTION")]
$reviews = []
$target = nil
unless %w[new status no_build processing internal_only compliance wrong_version wrong_app response_lost].include?($scenario)
  $target = FakeVersion.new("target-id", "1.0.1", "PREPARE_FOR_SUBMISSION")
  $target.release_type = "MANUAL"
  $versions << $target
end
case $scenario
when "no_build" then $builds = []
when "processing" then $builds = [make_build("570", "PROCESSING")]
when "expired" then $builds.each { |build| build.expired = true }
when "compliance" then $builds[1].uses_non_exempt_encryption = nil
when "wrong_version" then $builds[1].app_version = "2.0"
when "wrong_app" then $builds[1].app_id = "other-app"
when "conflicting_version" then $versions << FakeVersion.new("other-id", "2.0", "PREPARE_FOR_SUBMISSION")
when "draft_other_items", "draft_resume"
  review = FakeReview.new
  reference = $scenario == "draft_resume" ? $target : OpenStruct.new(id: "other-version")
  review.items = [OpenStruct.new(app_store_version: reference)]
  $reviews << review
  if $scenario == "draft_resume"
    $target.app_version_state = "READY_FOR_REVIEW"
    $target.build = $builds[1]
    $target.release_type = "AFTER_APPROVAL"
    $target.localizations.each { |localization| localization.whats_new = $notes }
  end
when "already_submitted", "queued_different_build", "queued_different_notes"
  $target.app_version_state = "WAITING_FOR_REVIEW"
  $target.release_type = "AFTER_APPROVAL"
  $target.build = $scenario == "queued_different_build" ? $builds[2] : $builds[1]
  $target.localizations.each { |localization| localization.whats_new = $notes } unless $scenario == "queued_different_notes"
  review = FakeReview.new
  review.state = "WAITING_FOR_REVIEW"
  $reviews << review
end

begin
  load ARGV.fetch(0)
  PodHavenAppStore.define_singleton_method(:sleep) { |seconds| $events << ["sleep", seconds] }
  options = { mode: ENV.fetch("APPSTORE_MODE", "submit"), version: "1.0.1", build: ENV["APPSTORE_BUILD"] }
  if $scenario == "response_lost"
    begin
      PodHavenAppStore.run(options)
    rescue StandardError => error
      raise unless error.message == "Submission response lost"
    end
  end
  PodHavenAppStore.run(options)
  raise "Description changed" unless $versions.all? { |version| version.localizations.all? { |locale| locale.description == "Existing description and screenshots" } }
rescue StandardError => error
  warn error.message
  exit 1
ensure
  puts JSON.generate($events)
end
