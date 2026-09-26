require "pilot"
require "pilot/options"
require "fastlane_core/build_watcher"

module PodHavenTestFlight
  UI = FastlaneCore::UI

  def self.run(options)
    notes = ENV.fetch("PODHAVEN_TESTFLIGHT_NOTES", "")
    UI.user_error!("TestFlight notes must not be blank.") if notes.strip.empty?
    UI.user_error!("TestFlight notes must be at most 4000 bytes.") if notes.bytesize > 4000

    timeout = ENV.fetch("PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS", "7200")
    unless timeout.match?(/\A[1-9][0-9]*\z/)
      UI.user_error!("PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS must be a positive whole number of seconds.")
    end

    key_path = ENV.fetch("ASC_KEY_PATH", "")
    unless key_path.empty?
      Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
        key_id: ENV.fetch("ASC_KEY_ID"),
        issuer_id: ENV.fetch("ASC_ISSUER_ID"),
        filepath: key_path
      )
    end

    config = FastlaneCore::Configuration.create(Pilot::Options.available_options, {
      app_identifier: "com.artisanalsoftware.PodHaven",
      app_platform: "ios",
      username: ENV["FASTLANE_USER"],
      distribute_only: true,
      distribute_external: true,
      changelog: notes,
      notify_external_testers: true,
      submit_beta_review: true,
      expire_previous_builds: false,
      reject_build_waiting_for_review: false
    })
    manager = Pilot::BuildManager.new
    manager.start(config)
    app = manager.app
    groups = app.get_beta_groups(filter: { name: "Everyone", isInternalGroup: "false" })
    groups = groups.select { |group| group.name == "Everyone" && group.is_internal_group == false }
    UI.user_error!("Expected exactly one external TestFlight group named Everyone.") unless groups.length == 1
    group = groups.first
    version = options[:version].to_s
    number = options[:build].to_s
    unless version.match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/) && number.match?(/\A[0-9]+\z/)
      UI.user_error!("An exact TestFlight app version and numeric build number are required.")
    end
    if options[:preflight].to_s == "true" || options[:prepare].to_s == "true"
      result = prepare_review(app, version, number, expire_waiting: options[:prepare].to_s == "true")
      UI.success("Confirmed the external Everyone group, App Store Connect login, and beta review availability.") if result == :ready
      return
    end
    begin
      build = FastlaneCore::BuildWatcher.wait_for_build_processing_to_be_complete(
        app_id: app.id,
        platform: "IOS",
        app_version: version,
        build_version: number,
        poll_interval: 30,
        timeout_duration: timeout.to_i,
        select_latest: false,
        wait_for_build_beta_detail_processing: true,
        return_spaceship_testflight_build: false
      )
    rescue FastlaneCore::Interface::FastlaneCrash => error
      raise unless error.message == "FastlaneCore::BuildWatcher exceeded the '#{timeout.to_i}' seconds, Stopping now!"
      UI.user_error!(
        "Apple has not made #{version} (#{number}) ready for TestFlight after #{timeout} seconds. " \
        "The upload is preserved; no distribution was attempted. Check TestFlight's Build Uploads in " \
        "App Store Connect for processing errors. If it is still processing, retry the same command " \
        "with the same --notes. Set PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS to allow a longer wait."
      )
    end
    unless Gem::Version.new(build.app_version) == Gem::Version.new(version) && build.version == number &&
           build.app_id == app.id && build.platform == "IOS"
      UI.user_error!("Apple returned a different app, platform, version, or build; no distribution was attempted.")
    end
    unless build.processing_state == "VALID" && build.expired == false
      UI.user_error!("Build #{version} (#{number}) is invalid or expired.")
    end
    if build.uses_non_exempt_encryption.nil? || build.missing_export_compliance?
      UI.user_error!("Complete export compliance for this build in App Store Connect, then retry.")
    end
    if build.ready_for_beta_submission?
      return if prepare_review(app, version, number, expire_waiting: true) == :new_version
    end

    config[:app_version] = version
    config[:build_number] = number
    config[:groups] = [group.id]
    begin
      manager.distribute(config, build: build)
    rescue Spaceship::UnexpectedResponse => error
      raise unless error.message.include?("Another build is in review")
      UI.message("Apple rejected the beta review submission: #{error.message}")
      return if prepare_review(app, version, number, expire_waiting: false) == :new_version
      UI.user_error!("Apple still reports another build in beta review. Retry the same testflight command with the same notes; the upload is preserved.")
    end

    assigned = Spaceship::ConnectAPI.get_beta_groups(filter: { builds: build.id }).all_pages.flat_map(&:to_models)
    unless assigned.any? { |candidate| candidate.id == group.id }
      UI.user_error!("Apple has not confirmed this build's assignment to Everyone. Retry the command.")
    end
    confirmed = Spaceship::ConnectAPI::Build.get(build_id: build.id)
    state = confirmed.build_beta_detail.external_build_state
    accepted = %w[WAITING_FOR_BETA_REVIEW IN_BETA_REVIEW BETA_APPROVED READY_FOR_BETA_TESTING IN_BETA_TESTING]
    unless accepted.include?(state)
      UI.user_error!("Assigned to Everyone, but external testing needs attention: #{state}.")
    end
    UI.success("Confirmed #{version} (#{number}) in Everyone: #{state.tr('_', ' ').downcase}.")
  end

  def self.prepare_review(app, version, number, expire_waiting:)
    builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: version, platform: "IOS")
    builds = builds.select do |candidate|
      candidate.app_id == app.id && candidate.platform == "IOS" &&
        Gem::Version.new(candidate.app_version) == Gem::Version.new(version) && candidate.expired == false
    end
    target = builds.find { |candidate| candidate.version == number }
    return :ready if target && !target.ready_for_beta_submission?

    conflicts = builds.select do |candidate|
      candidate.version != number && %w[WAITING_FOR_BETA_REVIEW IN_BETA_REVIEW].include?(candidate.build_beta_detail&.external_build_state)
    end
    return :ready if conflicts.empty?
    labels = conflicts.map { |candidate| "#{candidate.app_version} (#{candidate.version}): #{candidate.build_beta_detail.external_build_state}" }.join(", ")
    unless conflicts.length == 1 && conflicts.first.version.match?(/\A[0-9]+\z/) && conflicts.first.version.to_i < number.to_i
      UI.user_error!("Cannot replace beta review submissions: #{labels}. Expected one older build of the same version.")
    end
    previous = conflicts.first
    return request_next_version(version, previous) if previous.build_beta_detail.external_build_state == "IN_BETA_REVIEW"
    return :ready unless expire_waiting

    confirmed = Spaceship::ConnectAPI::Build.get(build_id: previous.id)
    unless confirmed.id == previous.id && confirmed.app_id == app.id && confirmed.platform == "IOS" &&
           confirmed.app_version == previous.app_version && confirmed.version == previous.version
      UI.user_error!("Apple returned a different build before cancellation. Retry the command.")
    end
    return :ready if confirmed.expired == true
    return request_next_version(version, confirmed) if confirmed.build_beta_detail.external_build_state == "IN_BETA_REVIEW"
    unless confirmed.expired == false && confirmed.build_beta_detail.external_build_state == "WAITING_FOR_BETA_REVIEW"
      UI.user_error!("Build #{version} (#{confirmed.version}) is no longer waiting for beta review. Retry the command.")
    end
    UI.message("Expiring #{version} (#{confirmed.version}) to replace its waiting beta review submission.")
    begin
      confirmed.expire!
    rescue Spaceship::UnexpectedResponse => error
      UI.message("Apple rejected build expiration: #{error.message}")
      latest = Spaceship::ConnectAPI::Build.get(build_id: confirmed.id)
      return request_next_version(version, latest) if latest.build_beta_detail.external_build_state == "IN_BETA_REVIEW"
      raise
    end
    latest = Spaceship::ConnectAPI::Build.get(build_id: confirmed.id)
    unless latest.expired == true
      return request_next_version(version, latest) if latest.build_beta_detail.external_build_state == "IN_BETA_REVIEW"
      UI.user_error!("Apple has not confirmed expiration of #{version} (#{confirmed.version}). Retry the command; no replacement was submitted.")
    end
    UI.message("Confirmed #{version} (#{confirmed.version}) expired.")
    :ready
  end

  def self.request_next_version(version, previous)
    path = ENV.fetch("PODHAVEN_TESTFLIGHT_NEXT_VERSION_PATH", "")
    if path.empty?
      UI.user_error!("Apple is reviewing #{version} (#{previous.version}). Run testflight without --reuse and with the same --notes to build and upload the next patch version.")
    end
    parts = version.split(".").map(&:to_i)
    parts[-1] += 1
    next_version = parts.join(".")
    UI.message("Apple is reviewing #{version} (#{previous.version}); a new upload as #{next_version} is required.")
    File.write(path, next_version)
    :new_version
  end
end
