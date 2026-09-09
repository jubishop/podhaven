require "json"
require "ostruct"

# Fake the external Fastlane and Apple boundaries while running our actual lane.
$LOADED_FEATURES.concat(["pilot.rb", "pilot/options.rb", "fastlane_core/build_watcher.rb"])
$events = []
$scenario = ENV.fetch("TESTFLIGHT_SCENARIO", "success")

module UI
  def self.user_error!(message)
    raise message
  end

  def self.success(message)
    $events << ["success", message]
  end
end

module Spaceship
  class ConnectAPI
    class << self
      attr_accessor :token
    end

    class Token
      def self.create(**options)
        $events << ["token", options]
        :token
      end
    end

    class Build
      def self.get(**options)
        $events << ["readback", options]
        state = $scenario == "rejected" ? "BETA_REJECTED" : "WAITING_FOR_BETA_REVIEW"
        OpenStruct.new(build_beta_detail: OpenStruct.new(external_build_state: state))
      end
    end
  end
end

module FastlaneCore
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
    $events << ["groups", filter]
    return [] if $scenario == "missing_group" || ($scenario == "unconfirmed" && filter[:builds])
    group = OpenStruct.new(id: "everyone-id", name: "Everyone", is_internal_group: $scenario == "internal_group")
    $scenario == "duplicate_group" ? [group, group] : [group]
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
    end
  end
end

def desc(_text); end

def lane(name)
  return unless name == :distribute_testflight
  yield(preflight: ENV["TESTFLIGHT_PREFLIGHT"], version: "1.0.1", build: "569")
end

begin
  load ARGV.fetch(0)
rescue StandardError => error
  warn error.message
  exit 1
ensure
  puts JSON.generate($events)
end
