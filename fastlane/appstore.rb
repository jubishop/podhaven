require "pilot"
require "pilot/options"
require "fastlane_core/build_watcher"

module PodHavenAppStore
  UI = FastlaneCore::UI
  EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
  CANCELLABLE = %w[READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW WAITING_FOR_EXPORT_COMPLIANCE PENDING_APPLE_RELEASE PENDING_DEVELOPER_RELEASE].freeze
  SUBMITTED = %w[WAITING_FOR_REVIEW IN_REVIEW ACCEPTED PENDING_APPLE_RELEASE PROCESSING_FOR_DISTRIBUTION READY_FOR_DISTRIBUTION].freeze
  REVIEW_STATES = %w[READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES CANCELING COMPLETING].freeze

  def self.run(options)
    mode = options[:mode].to_s
    number = options[:version].to_s
    UI.user_error!("Expected status, notes, preflight, or submit mode and an app version.") unless %w[status notes preflight submit].include?(mode) && !number.empty?
    notes = ENV["PODHAVEN_APPSTORE_NOTES"]
    if %w[preflight submit].include?(mode) && (notes.nil? || notes.strip.empty? || notes.length > 4000)
      UI.user_error!("Public release notes must contain 1 to 4000 characters.")
    end

    if %w[preflight submit].include?(mode) && !number.match?(/\A(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))?\z/)
      UI.user_error!("App Store release versions must have zero or one dot, such as 2 or 2.1.")
    end
    if mode == "submit" && options[:build].to_s.empty?
      UI.user_error!("An exact uploaded build number is required for submission.")
    end

    key_path = ENV.fetch("ASC_KEY_PATH", "")
    unless key_path.empty?
      Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
        key_id: ENV.fetch("ASC_KEY_ID"), issuer_id: ENV.fetch("ASC_ISSUER_ID"), filepath: key_path
      )
    end
    manager = Pilot::BuildManager.new
    manager.start(FastlaneCore::Configuration.create(Pilot::Options.available_options, {
      app_identifier: "com.artisanalsoftware.PodHaven", app_platform: "ios", username: ENV["FASTLANE_USER"]
    }))
    app = manager.app
    if mode == "notes"
      builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, platform: "IOS", sort: "-uploadedDate")
      latest = builds.find { |candidate| candidate.app_version.match?(/\A[0-9]+\.[0-9]+\.[0-9]+\z/) }
      UI.user_error!("No TestFlight build is available. Supply public release notes with --notes.") unless latest
      localizations = latest.get_beta_build_localizations
      localization = localizations.find { |candidate| candidate.locale == app.primary_locale }
      localization ||= localizations.find { |candidate| candidate.locale == "en-US" }
      notes = localization&.whats_new
      if notes.nil? || notes.strip.empty? || notes.length > 4000
        UI.user_error!("The latest TestFlight build #{latest.app_version} (#{latest.version}) has no usable public notes. Supply --notes.")
      end
      File.write(ENV.fetch("PODHAVEN_APPSTORE_NOTES_PATH"), notes)
      UI.message("Using #{localization.locale} notes from TestFlight #{latest.app_version} (#{latest.version}) as public release notes.")
      return
    end
    if mode == "submit"
      build = FastlaneCore::BuildWatcher.wait_for_build_processing_to_be_complete(
        app_id: app.id, platform: "IOS", app_version: number, build_version: options[:build].to_s,
        poll_interval: 30, timeout_duration: 1800, select_latest: false,
        wait_for_build_beta_detail_processing: true, return_spaceship_testflight_build: false
      )
      unless Gem::Version.new(build.app_version) == Gem::Version.new(number) && build.version == options[:build].to_s &&
             build.platform == "IOS" && build.app_id == app.id
        UI.user_error!("Apple returned a different app, version, platform, or build. Nothing was submitted.")
      end
      unless build.processing_state == "VALID" && build.expired == false
        UI.user_error!("Build #{number} (#{build.version}) is invalid or expired.")
      end
      audience = Spaceship::ConnectAPI.get_build(build_id: build.id).body.fetch("data").fetch("attributes")["buildAudienceType"]
      UI.user_error!("Build #{build.version} is not confirmed as App Store eligible: #{audience || 'unknown audience'}.") unless audience == "APP_STORE_ELIGIBLE"
      if build.uses_non_exempt_encryption.nil? || build.missing_export_compliance?
        UI.user_error!("Complete export compliance for this build in App Store Connect, then retry.")
      end
      UI.message("Selected PodHaven #{number} (build #{build.version}) for automatic release after approval.")
    end
    versions = app.get_app_store_versions(filter: { platform: "IOS" }, includes: "build")
    reviews = app.get_review_submissions(filter: { platform: "IOS", state: REVIEW_STATES.join(",") },
                                       includes: "appStoreVersionForReview")
    if mode == "status"
      builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: number, platform: "IOS", sort: "-uploadedDate")
      UI.message("Current local app version: #{number}")
      live = versions.select { |version| version.app_version_state == "READY_FOR_DISTRIBUTION" }
      live_numbers = live.empty? ? "none" : live.map(&:version_string).join(", ")
      UI.message("Live App Store version: #{live_numbers}")
      versions.reject { |version| %w[READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION].include?(version.app_version_state) }.each do |version|
        UI.message("App Store #{version.version_string} (build #{version.build&.version || 'none'}): #{version.app_version_state}; release #{version.release_type}")
      end
      reviews.each { |review| UI.message("Review #{review.id}: #{review.state}") }
      UI.message("Uploaded builds for #{number} (newest first, showing up to 10):")
      UI.message("None.") if builds.empty?
      builds.first(10).each do |build|
        UI.message("  #{build.version}: #{build.processing_state}#{build.expired ? ', expired' : ''}")
      end
      return
    end

    matching_versions = versions.select { |version| Gem::Version.new(version.version_string) == Gem::Version.new(number) }
    UI.user_error!("More than one App Store version matches #{number}.") if matching_versions.length > 1
    target = matching_versions.first
    if target && SUBMITTED.include?(target.app_version_state)
      unless target.build && target.build.version == options[:build].to_s
        UI.user_error!("This version is already submitted with a different build. Retry the original release command.")
      end
      build = target.build if mode == "preflight"
      verify_release(target.id, build, notes)
      UI.success("Already submitted: #{number} (#{build.version}), #{target.app_version_state}; automatic release after approval.")
      return
    end
    if target && !(EDITABLE + ["READY_FOR_REVIEW"]).include?(target.app_version_state)
      UI.user_error!("App Store #{number} cannot be submitted in state #{target.app_version_state}.")
    end
    conflicts = versions.reject do |version|
      version.id == target&.id || %w[READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION].include?(version.app_version_state)
    end
    replacement = conflicts.first if !target && conflicts.length == 1 &&
                                    Gem::Version.new(conflicts.first.version_string) < Gem::Version.new(number) &&
                                    (EDITABLE + CANCELLABLE).include?(conflicts.first.app_version_state)
    unless conflicts.empty? || replacement
      pending = conflicts.map { |version| "#{version.version_string} (#{version.app_version_state})" }.join(", ")
      UI.user_error!("Cannot replace pending App Store versions: #{pending}. Expected one older editable version or cancellable submission.")
    end
    live = versions.select { |version| version.app_version_state == "READY_FOR_DISTRIBUTION" }
    if live.any? { |version| Gem::Version.new(version.version_string) >= Gem::Version.new(number) }
      UI.user_error!("Choose a higher app version with bin/version and upload a new build before submitting.")
    end
    UI.user_error!("Multiple App Store review submissions are active; resolve them in App Store Connect.") if reviews.length > 1
    review = reviews.first
    items = review ? Spaceship::ConnectAPI::ReviewSubmissionItem.all(review_submission_id: review.id, includes: "appStoreVersion") : []
    if replacement
      if review
        unless review.state != "COMPLETING" && items.length == 1 && items.first.app_store_version&.id == replacement.id
          UI.user_error!("The pending review cannot be replaced: it is completing or contains other items. Resolve it in App Store Connect.")
        end
      elsif !EDITABLE.include?(replacement.app_version_state)
        UI.user_error!("No cancellable review was found for App Store #{replacement.version_string}. Check App Store Connect before retrying.")
      end
      UI.message("Will replace App Store #{replacement.version_string} (#{replacement.app_version_state}) with #{number} after the new build is ready.")
    else
      if review && review.state != "READY_FOR_REVIEW"
        UI.user_error!("An App Store review is already active: #{review.state}. Use bin/appstore --status to check it.")
      end
      unless items.empty? || (items.length == 1 && target && items.first.app_store_version&.id == target.id)
        UI.user_error!("The draft review contains other items. Resolve it in App Store Connect before submitting.")
      end
    end

    if mode == "preflight"
      UI.success("App Store #{number} is ready for a release upload and submission.")
      return
    end

    if replacement
      target = replace_version(replacement, review, number)
      review = nil
      items = []
    end
    unless target
      target = Spaceship::ConnectAPI.post_app_store_version(app_id: app.id, attributes: {
        versionString: number, platform: "IOS", releaseType: "AFTER_APPROVAL"
      }).first
    end
    if target.app_version_state == "READY_FOR_REVIEW"
      verify_release(target.id, build, notes)
    else
      localizations = target.get_app_store_version_localizations
      UI.user_error!("Apple has not supplied the version's listing localizations. Retry after checking App Store Connect.") if localizations.empty?
      target.update(attributes: { releaseType: "AFTER_APPROVAL" }) unless target.release_type == "AFTER_APPROVAL"
      target.select_build(build_id: build.id) unless target.build&.id == build.id
      localizations.each do |localization|
        localization.update(attributes: { whatsNew: notes }) unless localization.whats_new == notes
      end
      verify_release(target.id, build, notes)
    end

    review ||= app.create_review_submission(platform: "IOS")
    review.add_app_store_version_to_review_items(app_store_version_id: target.id) if items.empty?
    wait_for_version(target.id, ["READY_FOR_REVIEW"])
    review.submit_for_review
    confirmed = wait_for_version(target.id, SUBMITTED)
    verify_release(target.id, build, notes)
    UI.success("Submitted #{number} (#{build.version}): #{confirmed.app_version_state}; automatic release after approval.")
  end

  def self.replace_version(version, review, number)
    previous_number = version.version_string
    if review
      unless review.state == "CANCELING"
        UI.message("Cancelling the App Store #{previous_number} submission...")
        review.cancel_submission
      end
      12.times do |attempt|
        review = Spaceship::ConnectAPI::ReviewSubmission.get(review_submission_id: review.id)
        break if review.state == "COMPLETE"
        UI.message("Waiting for Apple to cancel the previous review (#{review.state})...")
        sleep(5) unless attempt == 11
      end
      UI.user_error!("Apple has not confirmed review cancellation. Retry the same appstore command.") unless review.state == "COMPLETE"
    end
    version = wait_for_version(version.id, EDITABLE)
    unless version.version_string == previous_number
      UI.user_error!("The pending version changed during replacement. Check App Store Connect before retrying.")
    end
    if version.build
      version.select_build(build_id: nil)
      version = Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id: version.id, includes: "build")
    end
    unless version.build.nil? && version.version_string == previous_number && EDITABLE.include?(version.app_version_state)
      UI.user_error!("Apple has not confirmed the old build was removed from #{previous_number}. Retry the same appstore command.")
    end
    version.update(attributes: { versionString: number })
    confirmed = Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id: version.id, includes: "build")
    unless confirmed.version_string == number && confirmed.build.nil? && EDITABLE.include?(confirmed.app_version_state)
      UI.user_error!("Apple has not confirmed the draft changed to #{number}. Retry the same appstore command.")
    end
    UI.success("Replaced App Store #{previous_number} with the #{number} draft.")
    confirmed
  end

  def self.verify_release(id, build, notes)
    version = Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id: id, includes: "build")
    unless version.build&.id == build.id && version.release_type == "AFTER_APPROVAL"
      UI.user_error!("The selected build or automatic-release setting does not match. No submission was confirmed.")
    end
    localizations = version.get_app_store_version_localizations
    unless !localizations.empty? && localizations.all? { |localization| localization.whats_new == notes }
      UI.user_error!("The public release notes do not match. No submission was confirmed.")
    end
  end

  def self.wait_for_version(id, states)
    12.times do |attempt|
      version = Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id: id, includes: "build")
      return version if states.include?(version.app_version_state)
      UI.message("Waiting for Apple to confirm the version state (currently #{version.app_version_state})...")
      sleep(5) unless attempt == 11
    end
    UI.user_error!("Apple has not confirmed the version state. Run bin/appstore --status to inspect it, then retry the same submission if needed.")
  end
end
