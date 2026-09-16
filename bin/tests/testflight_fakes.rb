require "json"
require "ostruct"

# Fake the external Fastlane and Apple boundaries while running our actual lane.
$LOADED_FEATURES.concat(["pilot.rb", "pilot/options.rb", "fastlane_core/build_watcher.rb"])
$events = []
$scenario = ENV.fetch("TESTFLIGHT_SCENARIO", "success")

module UI
  def self.message(message)
    $events << ["message", message]
  end

  def self.user_error!(message)
    raise message
  end

  def self.success(message)
    $events << ["success", message]
  end
end

module Spaceship
  class UnexpectedResponse < StandardError; end

  class ConnectAPI
    class << self
      attr_accessor :token
    end

    def self.get_beta_groups(filter:)
      $events << ["groups", filter.dup]
      if filter[:app] && filter[:builds]
        raise "Only one relationship filter can be applied."
      end

      group = OpenStruct.new(id: "everyone-id", name: "Everyone", is_internal_group: $scenario == "internal_group")
      groups = $scenario == "duplicate_group" ? [group, group] : [group]
      groups = [] if $scenario == "missing_group"
      pages = [groups]
      if filter[:builds] && %w[unconfirmed paginated].include?($scenario)
        other = OpenStruct.new(id: "other-id", name: "Everyone", is_internal_group: false)
        pages = [[other]]
        pages << [group] if $scenario == "paginated"
      end
      OpenStruct.new(to_models: pages.first, all_pages: pages.map { |models| OpenStruct.new(to_models: models) })
    end

    class Token
      def self.create(**options)
        $events << ["token", options]
        :token
      end
    end

    class Build
      attr_accessor :id, :app_version, :version, :platform, :app_id, :expired, :build_beta_detail

      def initialize(id: "build-id", number: "569", state: "READY_FOR_BETA_SUBMISSION", version: "1.0.1", platform: "IOS")
        @id, @version, @app_version, @platform = id, number, version, platform
        @app_id = "podhaven-id"
        @expired = false
        @build_beta_detail = OpenStruct.new(external_build_state: state)
      end

      def ready_for_beta_submission?
        build_beta_detail.external_build_state == "READY_FOR_BETA_SUBMISSION"
      end

      def expire!
        $events << ["expire", id]
        raise Spaceship::UnexpectedResponse, "Expiration failed" if %w[expire_error expire_review_started].include?($scenario)
        $expired = true
      end

      def self.all(**options)
        $events << ["builds", options]
        target = new
        target.build_beta_detail.external_build_state = "IN_BETA_REVIEW" if $scenario == "target_in_review"
        previous = new(id: "older-id", number: "568", state: "WAITING_FOR_BETA_REVIEW")
        previous.build_beta_detail.external_build_state = "IN_BETA_REVIEW" if $scenario == "active_review"
        previous.build_beta_detail.external_build_state = "IN_BETA_REVIEW" if $scenario == "submission_started" && $events.any? { |event| event.first == "distribute" }
        previous.build_beta_detail.external_build_state = "IN_BETA_TESTING" if $scenario == "approved_previous"
        previous.expired = true if $scenario == "expired_previous"
        previous.version = "570" if $scenario == "newer_review"
        previous.app_version = "1.0.2" if $scenario == "other_version"
        previous.platform = "MAC_OS" if $scenario == "other_platform"
        conflicts = %w[waiting_review active_review target_in_review approved_previous expired_previous newer_review
                       other_version other_platform multiple_reviews review_started review_finished expire_error
                       expire_unconfirmed expire_review_started].include?($scenario) ? [previous] : []
        conflicts = [previous] if $scenario == "submission_started" && $events.any? { |event| event.first == "distribute" }
        conflicts << new(id: "second-id", number: "567", state: "WAITING_FOR_BETA_REVIEW") if $scenario == "multiple_reviews"
        [target, *conflicts]
      end

      def self.get(**options)
        $events << ["readback", options]
        if options[:build_id] == "older-id"
          state = { "review_started" => "IN_BETA_REVIEW", "review_finished" => "IN_BETA_TESTING" }.fetch($scenario, "WAITING_FOR_BETA_REVIEW")
          state = "IN_BETA_REVIEW" if $scenario == "expire_review_started" && $events.include?(["expire", "older-id"])
          previous = new(id: "older-id", number: "568", state: state)
          previous.expired = $expired == true && $scenario != "expire_unconfirmed"
          return previous
        end
        state = $scenario == "rejected" ? "BETA_REJECTED" : "WAITING_FOR_BETA_REVIEW"
        OpenStruct.new(build_beta_detail: OpenStruct.new(external_build_state: state))
      end
    end
  end
end

module FastlaneCore
  UI = ::UI
  class Configuration
    def self.create(_options, values)
      values
    end
  end

  class BuildWatcher
    def self.wait_for_build_processing_to_be_complete(**options)
      $events << ["wait", options]
      raise "Processing timed out" if $scenario == "timeout"
      OpenStruct.new(
        id: "build-id", app_version: "1.0.1", version: $scenario == "wrong_build" ? "570" : "569",
        platform: $scenario == "wrong_platform" ? "MAC_OS" : "IOS",
        app_id: $scenario == "wrong_app" ? "other-app" : "podhaven-id",
        ready_for_beta_submission?: $scenario != "target_in_review",
        processing_state: $scenario == "invalid" ? "INVALID" : "VALID", expired: $scenario == "expired",
        uses_non_exempt_encryption: $scenario == "compliance" ? nil : false,
        missing_export_compliance?: false
      )
    end
  end
end

class FakeApp
  def id
    "podhaven-id"
  end

  def get_beta_groups(filter:)
    filter[:app] = id
    Spaceship::ConnectAPI.get_beta_groups(filter: filter).all_pages.flat_map(&:to_models)
  end
end

module Pilot
  class Options
    def self.available_options
      []
    end
  end

  class BuildManager
    def start(config)
      $events << ["login", config.dup]
    end

    def app
      FakeApp.new
    end

    def distribute(config, build:)
      $events << ["distribute", config.dup, build.id]
      if %w[submission_conflict submission_started].include?($scenario)
        raise Spaceship::UnexpectedResponse, "Another build is in review. - Another build in the same train is already in beta review."
      end
      raise Spaceship::UnexpectedResponse, "Apple authentication failed" if $scenario == "submission_error"
    end
  end
end

def desc(_text); end

def lane(name)
  return unless name == :distribute_testflight
  yield(preflight: ENV["TESTFLIGHT_PREFLIGHT"], prepare: ENV["TESTFLIGHT_PREPARE"], version: "1.0.1", build: "569")
end

begin
  load ARGV.fetch(0)
rescue StandardError => error
  warn error.message
  exit 1
ensure
  path = ENV["PODHAVEN_TESTFLIGHT_NEXT_VERSION_PATH"]
  $events << ["next_version", File.read(path)] if path && File.file?(path)
  puts JSON.generate($events)
end
