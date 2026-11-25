require "pilot"
require "pilot/options"
require_relative "connect"

module PodHavenTestFlight
  UI = FastlaneCore::UI
  APP_IDENTIFIER = "com.artisanalsoftware.PodHaven".freeze

  def self.run(options)
    base = options[:base].to_s == "true"
    notes = ENV.fetch("PODHAVEN_TESTFLIGHT_NOTES", "")
    UI.user_error!("TestFlight notes must not be blank.") if notes.strip.empty? && !base
    UI.user_error!("TestFlight notes must be at most 4000 bytes.") if notes.bytesize > 4000

    timeout = PodHavenConnect.processing_timeout
    PodHavenConnect.login!

    config = FastlaneCore::Configuration.create(Pilot::Options.available_options, {
      app_identifier: APP_IDENTIFIER,
      app_platform: "ios",
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
    group = everyone(app)
    if base
      tested, pending = latest_tested_build(group)
      File.write(ENV.fetch("PODHAVEN_TESTFLIGHT_BASE_PATH"), tested ? tested.version : "")
      pending_path = ENV.fetch("PODHAVEN_TESTFLIGHT_PENDING_PATH", "")
      File.write(pending_path, pending ? JSON.generate(pending) : "") unless pending_path.empty?
      return
    end
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
    build = PodHavenConnect.wait_for_build(app, version, number, timeout, "no distribution was attempted")
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
      UI.user_error!("Apple still reports another build in beta review. Retry the same testflight command; the upload is preserved.")
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

  def self.everyone(app)
    groups = app.get_beta_groups(filter: { name: "Everyone", isInternalGroup: "false" })
    groups = groups.select { |group| group.name == "Everyone" && group.is_internal_group == false }
    UI.user_error!("Expected exactly one external TestFlight group named Everyone.") unless groups.length == 1
    groups.first
  end

  # The tester options: remove, then add, then list, so a listing shows the changes.
  def self.manage_testers
    PodHavenConnect.login!
    manager = Pilot::BuildManager.new
    manager.start(FastlaneCore::Configuration.create(Pilot::Options.available_options, {
      app_identifier: APP_IDENTIFIER, app_platform: "ios"
    }))
    app = manager.app
    group = everyone(app)
    ENV.fetch("PODHAVEN_TESTERS_REMOVE", "").split("\n").reject(&:empty?).each { |email| remove_tester(group, email) }
    ENV.fetch("PODHAVEN_TESTERS_ADD", "").split("\n").reject(&:empty?).each { |email| add_tester(app, group, email) }
    list_testers(group) if ENV["PODHAVEN_TESTERS_LIST"] == "true"
  end

  # Spaceship's tester model omits the state attribute, so these read the raw resources.
  def self.testers(filter)
    Spaceship::ConnectAPI.get_beta_testers(filter: filter, limit: 200).all_pages.flat_map { |page| page.body.fetch("data") }
  end

  # The team's tester with this email, or the group's when a group is given. Apple ignores case in emails.
  def self.tester(email, group = nil)
    filter = { email: email }
    filter[:betaGroups] = group.id if group
    testers(filter).find { |found| found.dig("attributes", "email").to_s.casecmp?(email) }
  end

  # Apple lists a tester who left, or was removed from the app, as REVOKED.
  def self.member?(found)
    !found.nil? && found.dig("attributes", "state") != "REVOKED"
  end

  # A tester the team already has, such as one shared with another app, joins Everyone; anyone else is created in it.
  # Apple's documentation doesn't say whether either emails the invitation, so an uninvited tester gets one here.
  def self.add_tester(app, group, email)
    found = tester(email, group)
    added = !member?(found)
    if added
      existing = tester(email)
      if existing
        UI.message("Adding #{email}, already a TestFlight tester on the team, to Everyone.")
        Spaceship::ConnectAPI.add_beta_tester_to_group(beta_group_id: group.id, beta_tester_ids: [existing.fetch("id")])
      else
        UI.message("Adding #{email} to Everyone.")
        Spaceship::ConnectAPI.post_beta_tester_assignment(beta_group_ids: [group.id], attributes: { email: email })
      end
      found = tester(email, group)
      UI.user_error!("App Store Connect does not list #{email} in Everyone. Run bin/testflight --add-tester #{email} again.") unless found
    end
    state = found.dig("attributes", "state")
    if %w[NOT_INVITED REVOKED].include?(state)
      UI.message("App Store Connect lists #{email} as #{state}, so sending TestFlight's invitation.")
      Spaceship::ConnectAPI.test_flight_request_client.post("v1/betaTesterInvitations", {
        data: {
          type: "betaTesterInvitations",
          relationships: {
            app: { data: { type: "apps", id: app.id } },
            betaTester: { data: { type: "betaTesters", id: found.fetch("id") } }
          }
        }
      })
      UI.success("#{email} is in Everyone and invited to TestFlight.")
    elsif added
      UI.success("#{email} is in Everyone; TestFlight lists them as #{state}.")
    else
      UI.success("#{email} is already in Everyone as #{state}; nothing changed.")
    end
  end

  # Takes the email out of Everyone only, so the tester stays on the team and in other groups and apps.
  def self.remove_tester(group, email)
    found = tester(email, group)
    unless member?(found)
      UI.success("#{email} is not in Everyone; nothing changed.")
      return
    end
    UI.message("Removing #{email} from Everyone.")
    Spaceship::ConnectAPI.delete_beta_tester_from_beta_groups(beta_tester_id: found.fetch("id"), beta_group_ids: [group.id])
    if member?(tester(email, group))
      UI.user_error!("App Store Connect still lists #{email} in Everyone. Run bin/testflight --remove-tester #{email} again.")
    end
    UI.success("#{email} is no longer in Everyone.")
  end

  # Everyone's testers, those with an email first.
  def self.list_testers(group)
    found = testers(betaGroups: group.id).map do |resource|
      attributes = resource.fetch("attributes")
      name = [attributes["firstName"], attributes["lastName"]].reject { |part| part.to_s.empty? }.join(" ")
      { email: attributes["email"].to_s, name: name, state: attributes["state"], invite: attributes["inviteType"] }
    end
    if found.empty?
      UI.message("Everyone has no testers.")
      return
    end
    UI.message("Everyone has #{found.length} #{found.length == 1 ? 'tester' : 'testers'}:")
    found.sort_by { |each| [each[:email].empty? ? 1 : 0, (each[:email].empty? ? each[:name] : each[:email]).downcase] }
         .each do |each|
      who = if each[:email].empty?
              "#{each[:name].empty? ? 'No name' : each[:name]} (no email)"
            elsif each[:name].empty?
              each[:email]
            else
              "#{each[:name]} <#{each[:email]}>"
            end
      joined = each[:invite] == "PUBLIC_LINK" ? "joined through the public link" : "invited by email"
      UI.message("#{who}: #{each[:state] || 'no state'}, #{joined}")
    end
  end

  def self.latest_tested_build(group)
    page = Spaceship::ConnectAPI.get_builds(filter: { betaGroups: group.id, expired: "false" },
                                            includes: "buildBetaDetail,preReleaseVersion,betaAppReviewSubmission",
                                            sort: "-uploadedDate", limit: 50)
    pending = nil
    while page
      page.to_models.each do |candidate|
        next unless candidate.pre_release_version&.platform == "IOS"
        state = candidate.build_beta_detail&.external_build_state
        if state == "IN_BETA_TESTING"
          UI.message("Testers in Everyone have build #{candidate.version}.")
          return candidate, pending
        end
        next if pending
        # Spaceship's BetaAppReviewSubmission model omits submittedDate.
        submission = page.body.fetch("included", []).find do |item|
          item["type"] == "betaAppReviewSubmissions" && item["id"] == candidate.beta_app_review_submission&.id
        end
        pending = { build: candidate.version, version: candidate.app_version, state: state,
                    submitted: submission&.dig("attributes", "submittedDate") }
      end
      page = page.next_page
    end
    UI.message("No iOS build is in testing for Everyone.")
    [nil, pending]
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
      UI.user_error!("Apple is reviewing #{version} (#{previous.version}). Run testflight without --distribute-only to build and upload the next patch version.")
    end
    parts = version.split(".").map(&:to_i)
    parts[-1] += 1
    next_version = parts.join(".")
    UI.message("Apple is reviewing #{version} (#{previous.version}); a new upload as #{next_version} is required.")
    File.write(path, next_version)
    :new_version
  end
end
