require "fastlane_core/build_watcher"

# What the TestFlight and App Store lanes share: the API key login and the processing wait.
module PodHavenConnect
  UI = FastlaneCore::UI
  TIMEOUT_VARIABLE = "PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS".freeze
  DEFAULT_TIMEOUT_SECONDS = 2 * 60 * 60

  def self.processing_timeout
    value = ENV.fetch(TIMEOUT_VARIABLE, DEFAULT_TIMEOUT_SECONDS.to_s)
    UI.user_error!("#{TIMEOUT_VARIABLE} must be a positive whole number of seconds.") unless value.match?(/\A[1-9][0-9]*\z/)
    value.to_i
  end

  # Requests use the API key only, since an Apple ID login can ask for a two-factor code.
  def self.login!
    path, key_id, issuer_id = %w[ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID].map { |name| ENV.fetch(name, "") }
    if [path, key_id, issuer_id].any?(&:empty?)
      UI.user_error!("App Store Connect requests need an API key: set ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID.")
    end
    Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(key_id: key_id, issuer_id: issuer_id, filepath: path)
  end

  # Waits for Apple to process the exact build. A timeout says what the stopped command left undone.
  def self.wait_for_build(app, version, number, timeout, unattempted)
    FastlaneCore::BuildWatcher.wait_for_build_processing_to_be_complete(
      app_id: app.id,
      platform: "IOS",
      app_version: version,
      build_version: number,
      poll_interval: 30,
      timeout_duration: timeout,
      select_latest: false,
      wait_for_build_beta_detail_processing: true,
      return_spaceship_testflight_build: false
    )
  rescue FastlaneCore::Interface::FastlaneCrash => error
    raise unless error.message == "FastlaneCore::BuildWatcher exceeded the '#{timeout}' seconds, Stopping now!"
    UI.user_error!(
      "Apple has not finished processing #{version} (#{number}) after #{timeout} seconds. " \
      "The upload is preserved; #{unattempted}. Check TestFlight's Build Uploads in " \
      "App Store Connect for processing errors. If it is still processing, rerun the same command; " \
      "it reuses the upload. Set #{TIMEOUT_VARIABLE} to allow a longer wait."
    )
  end
end
