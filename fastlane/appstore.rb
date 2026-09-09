require "pilot"
require "pilot/options"

module PodHavenAppStore
  UI = FastlaneCore::UI
  EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
  SUBMITTED = %w[WAITING_FOR_REVIEW IN_REVIEW ACCEPTED PENDING_APPLE_RELEASE PROCESSING_FOR_DISTRIBUTION READY_FOR_DISTRIBUTION].freeze
  REVIEW_STATES = %w[READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES CANCELING COMPLETING].freeze

  def self.run(options)
    mode = options[:mode].to_s
    number = options[:version].to_s
    UI.user_error!("Expected status or submit mode and a current app version.") unless %w[status submit].include?(mode) && !number.empty?
    notes = ENV["PODHAVEN_APPSTORE_NOTES"]
    if mode == "submit" && (notes.nil? || notes.strip.empty? || notes.length > 4000)
      UI.user_error!("Public release notes must contain 1 to 4000 characters.")
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
    versions = app.get_app_store_versions(filter: { platform: "IOS" }, includes: "build")
    reviews = app.get_review_submissions(filter: { platform: "IOS", state: REVIEW_STATES.join(",") },
                                       includes: "appStoreVersionForReview")
    builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: number,
                                            build_number: options[:build], platform: "IOS", sort: "-uploadedDate")
    if mode == "status"
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

    matches = builds.select { |build| build.processing_state == "VALID" && build.expired == false }
    UI.user_error!("No processed, unexpired build exists for #{number}. Upload with bin/shipit and let Apple finish processing.") if matches.empty?
    UI.user_error!("More than one build matches the requested build number.") if options[:build] && matches.length != 1
    build = matches.first
    unless Gem::Version.new(build.app_version) == Gem::Version.new(number) && build.platform == "IOS" && build.app_id == app.id
      UI.user_error!("Apple returned a build for a different app, version, or platform.")
    end
    audience = Spaceship::ConnectAPI.get_build(build_id: build.id).body.fetch("data").fetch("attributes")["buildAudienceType"]
    UI.user_error!("Build #{build.version} is not confirmed as App Store eligible: #{audience || 'unknown audience'}.") unless audience == "APP_STORE_ELIGIBLE"
    if build.uses_non_exempt_encryption.nil? || build.missing_export_compliance?
      UI.user_error!("Complete export compliance for this build in App Store Connect, then retry.")
    end
    UI.message("Selected PodHaven #{number} (build #{build.version}) for automatic release after approval.")

    matching_versions = versions.select { |version| Gem::Version.new(version.version_string) == Gem::Version.new(number) }
    UI.user_error!("More than one App Store version matches #{number}.") if matching_versions.length > 1
    target = matching_versions.first
    if target && SUBMITTED.include?(target.app_version_state)
      verify_release(target.id, build, notes)
      UI.success("Already submitted: #{number} (#{build.version}), #{target.app_version_state}; automatic release after approval.")
      return
    end
    if target && !(EDITABLE + ["READY_FOR_REVIEW"]).include?(target.app_version_state)
      UI.user_error!("App Store #{number} cannot be submitted in state #{target.app_version_state}.")
    end
    conflicts = versions.reject { |version| version.id == target&.id }.select do |version|
      (EDITABLE + %w[READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW ACCEPTED PENDING_APPLE_RELEASE PENDING_DEVELOPER_RELEASE]).include?(version.app_version_state)
    end
    UI.user_error!("Another App Store version is pending: #{conflicts.map(&:version_string).join(', ')}.") unless conflicts.empty?
    live = versions.select { |version| version.app_version_state == "READY_FOR_DISTRIBUTION" }
    if live.any? { |version| Gem::Version.new(version.version_string) >= Gem::Version.new(number) }
      UI.user_error!("Choose a higher app version with bin/version and upload a new build before submitting.")
    end
    UI.user_error!("Multiple App Store review submissions are active; resolve them in App Store Connect.") if reviews.length > 1
    review = reviews.first
    if review && review.state != "READY_FOR_REVIEW"
      UI.user_error!("An App Store review is already active: #{review.state}. Use bin/appstore to check it.")
    end
    items = review ? Spaceship::ConnectAPI::ReviewSubmissionItem.all(review_submission_id: review.id, includes: "appStoreVersion") : []
    unless items.empty? || (items.length == 1 && target && items.first.app_store_version&.id == target.id)
      UI.user_error!("The draft review contains other items. Resolve it in App Store Connect before submitting.")
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
      version = Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id: id)
      return version if states.include?(version.app_version_state)
      UI.message("Waiting for Apple to confirm the version state (currently #{version.app_version_state})...")
      sleep(5) unless attempt == 11
    end
    UI.user_error!("Apple has not confirmed the version state. Run bin/appstore to inspect it, then retry the same submission if needed.")
  end
end
