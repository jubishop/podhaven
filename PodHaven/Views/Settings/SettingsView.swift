// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SettingsView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.userSettings) private var userSettings

  private static let log = Log.as(LogSubsystem.SettingsView.main)
  private static let githubURL = URL(string: "https://github.com/jubishop/podhaven")
  private static let discordURL = URL(string: "https://discord.gg/cMCJeuVY2f")
  private static let websiteURL = URL(string: "https://artisanalsoftware.com/podhaven")

  @State private var tempMaxQueueLength: Double
  @State private var tempMaxRecommendedEpisodes: Double

  private let viewModel = SettingsViewModel()

  init() {
    self._tempMaxQueueLength = State(
      initialValue: Double(Container.shared.userSettings().maxQueueLength)
    )
    self._tempMaxRecommendedEpisodes = State(
      initialValue: Double(Container.shared.userSettings().maxRecommendedEpisodesInUpNext)
    )
  }

  private var formattedCacheSize: String {
    let sizeGB = userSettings.cacheSizeLimitGB
    guard sizeGB < 1.0 else {
      return "\(sizeGB.formatted(decimalPlaces: 1)) GB"
    }
    let sizeMB = Int(sizeGB * 1000)
    return "\(sizeMB) MB"
  }

  private var formattedPlaybackRate: String {
    "\(userSettings.defaultPlaybackRate.formatted(decimalPlaces: 1))×"
  }

  private var formattedMaxQueueLength: String {
    "\(Int(tempMaxQueueLength)) ep"
  }

  private var formattedMaxRecommendedEpisodes: String {
    let count = Int(tempMaxRecommendedEpisodes)
    return count == 0 ? "Off" : "\(count) ep"
  }

  private var formattedPodcastAffinityWeight: String {
    let percent = Int((userSettings.podcastAffinityWeight * 100).rounded())
    return percent == 0 ? "Off" : "\(percent)%"
  }

  var body: some View {
    NavStack(manager: navigation.settings) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(
            value: Navigation.Destination.settingsSection(.opml),
            label: { Text("OPML") }
          )
        }

        Section("Organization") {
          NavigationLink(
            value: Navigation.Destination.settingsSection(.tags),
            label: { Text("Tags") }
          )
        }

        Section("Gestures") {
          NavigationLink(
            value: Navigation.Destination.settingsSection(.swipeActions),
            label: { Text("Swipe Left Actions") }
          )
        }

        Section("Playback") {
          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                The default playback speed for new episodes. \
                This rate will be applied when you start playing an episode for the first time.
                """
            ) {
              HStack {
                Text("Default Playback Rate")
                Spacer()
                Text(formattedPlaybackRate)
                  .foregroundStyle(.secondary)
              }
            }

            Slider(
              value: userSettings.$defaultPlaybackRate.binding,
              in: 0.8...2.0,
              step: 0.1
            )
          }

          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                Controls what happens when you use the Next Track button \
                on physical inputs like car controls, the lock screen, or control center. \
                Choose "Next Episode" to skip to the next episode in your queue, \
                "Skip Interval" to jump forward/backward using your custom skip interval, \
                or "Next Chapter" to navigate between chapters when available \
                (falls back to Skip Interval when no chapters are found).
                """
            ) {
              Text("Next Track Behavior")
              Spacer()
            }

            Picker("Next Track Behavior", selection: userSettings.$nextTrackBehavior.binding) {
              ForEach(UserSettings.NextTrackBehavior.allCases) { behavior in
                Text(behavior.rawValue).tag(behavior)
              }
            }
            .labelsHidden()
          }

          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                The time interval (in seconds) to skip forward when using skip controls \
                on the lock screen, control center, or in-app player.
                """
            ) {
              Text("Skip Forward Interval")
              Spacer()
            }

            Picker("Skip Forward Interval", selection: userSettings.$skipForwardInterval.binding) {
              Text("5 sec").tag(5.0)
              Text("10 sec").tag(10.0)
              Text("15 sec").tag(15.0)
              Text("30 sec").tag(30.0)
              Text("45 sec").tag(45.0)
              Text("60 sec").tag(60.0)
              Text("75 sec").tag(75.0)
              Text("90 sec").tag(90.0)
            }
            .labelsHidden()
          }

          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                The time interval (in seconds) to skip backward when using skip controls \
                on the lock screen, control center, or in-app player.
                """
            ) {
              Text("Skip Backward Interval")
              Spacer()
            }

            Picker("Skip Backward Interval", selection: userSettings.$skipBackwardInterval.binding)
            {
              Text("5 sec").tag(5.0)
              Text("10 sec").tag(10.0)
              Text("15 sec").tag(15.0)
              Text("30 sec").tag(30.0)
              Text("45 sec").tag(45.0)
              Text("60 sec").tag(60.0)
              Text("75 sec").tag(75.0)
              Text("90 sec").tag(90.0)
            }
            .labelsHidden()
          }

          SettingsRow(
            infoText: """
              When enabled, sliding the progress bar will temporarily replace the skip backward \
              button with an undo button, allowing you to return to your previous position \
              if you accidentally seek.
              """
          ) {
            Toggle("Enable Undo Seek", isOn: userSettings.$enableUndoSeek.binding)
          }

          SettingsRow(
            infoText: """
              When enabled, you can drag the progress bar to seek from the lock screen, \
              Control Center, and CarPlay. Disable to keep from accidentally moving your \
              position; the skip buttons and the progress display stay available.
              """
          ) {
            VStack(alignment: .leading, spacing: 24) {
              Text("Command Center Scrubbing")
              Toggle(
                "Command Center Scrubbing",
                isOn: userSettings.$commandCenterScrubbingEnabled.binding
              )
              .labelsHidden()
            }
            Spacer(minLength: 0)
          }

          SettingsRow(
            infoText: """
              Choose what the Like button does on car controls, headphones, \
              and other remotes to the currently playing episode. \
              "Add Tag" assigns a tag you pick; it appears only once you have tags.
              """
          ) {
            Text("Like Button")
            Spacer()
            CommandCenterLikeMenu()
          }

          SettingsRow(
            infoText: """
              Choose what the Dislike button does on car controls, headphones, \
              and other remotes to the currently playing episode. \
              "Add Tag" assigns a tag you pick; it appears only once you have tags.
              """
          ) {
            Text("Dislike Button")
            Spacer()
            CommandCenterDislikeMenu()
          }
        }

        Section("Appearance") {
          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                Choose how the app appearance adapts to your preferences.  \
                'System' follows your device's light or dark mode setting, \
                while 'Light' and 'Dark' force that mode regardless of system settings.
                """
            ) {
              Text("Appearance Mode")
              Spacer()
            }

            Picker("", selection: userSettings.$appearanceMode.binding) {
              Text("System").tag(UserSettings.AppearanceMode.system)
              Text("Light").tag(UserSettings.AppearanceMode.light)
              Text("Dark").tag(UserSettings.AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
          }

          SettingsRow(
            infoText: """
              When enabled, \
              the Playbar will automatically shrink when you scroll down, \
              giving you more screen space to view content.  \
              Scroll back up to reveal them again.
              """
          ) {
            Toggle("Shrink Playbar", isOn: userSettings.$shrinkPlayBarOnScroll.binding)
          }

          SettingsRow(
            infoText: """
              When enabled, \
              episode lists will show the time remaining instead of the total duration \
              for episodes you've started listening to.
              """
          ) {
            Toggle(
              "Show Time Remaining",
              isOn: userSettings.$showTimeRemainingInEpisodeLists.binding
            )
          }
        }

        Section("Recommendations") {
          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                Controls how aggressively the engine strips out shared structure \
                from podcast embeddings before scoring. \
                'Focused' centers vectors against the corpus mean only, so recommendations \
                stay close to the podcasts you've already rated. \
                'Exploratory' additionally removes the top three principal components — \
                which empirically encode podcast *format* (daily news vs. long-form narrative) \
                rather than topic — opening up topical discovery across shows you haven't \
                engaged with yet.
                """
            ) {
              Text("Recommendation Diversity")
              Spacer()
            }

            Picker("", selection: userSettings.$recommendationDeconeMode.binding) {
              Text("Focused").tag(UserSettings.RecommendationDeconeMode.focused)
              Text("Exploratory").tag(UserSettings.RecommendationDeconeMode.exploratory)
            }
            .pickerStyle(.segmented)
          }

          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                How much weight to give a candidate's podcast affinity \
                (how positively you've rated other episodes from the same podcast) \
                versus its content similarity to your listening history. \
                Lower values favor pure content similarity; \
                higher values favor podcasts you've already engaged with. \
                The similarity term always takes the remaining weight.
                """
            ) {
              HStack {
                Text("Podcast Affinity")
                Spacer()
                Text(formattedPodcastAffinityWeight)
                  .foregroundStyle(.secondary)
              }
            }
            Slider(
              value: userSettings.$podcastAffinityWeight.binding,
              in: 0.0...0.5,
              step: 0.05
            )
          }
        }

        Section("Up Next") {
          SettingsRow(
            infoText: """
              When enabled, \
              the currently playing episode will be shown at the top of the Up Next queue.
              """
          ) {
            Toggle("Show Now Playing", isOn: userSettings.$showNowPlayingInUpNext.binding)
          }

          SettingsRow(
            infoText: """
              When enabled, \
              episodes in the Up Next queue will always display the podcast artwork \
              instead of the episode-specific artwork.
              """
          ) {
            VStack(alignment: .leading, spacing: 24) {
              VStack(alignment: .leading, spacing: 2) {
                Text("Always Show Podcast Art")
                Text("in Queue")
                  .foregroundStyle(.secondary)
              }
              Toggle(
                "Always Show Podcast Art in Queue",
                isOn: userSettings.$alwaysShowPodcastImageInUpNext.binding
              )
              .labelsHidden()
            }
            Spacer(minLength: 0)
          }

          SettingsRow(
            infoText: """
              When enabled, the currently playing episode will always display \
              the podcast artwork instead of the episode-specific artwork — \
              in the Playbar, the lock screen, the Now Playing widget, \
              and at the top of the Up Next queue.
              """
          ) {
            VStack(alignment: .leading, spacing: 24) {
              VStack(alignment: .leading, spacing: 2) {
                Text("Always Show Podcast Art")
                Text("for Now Playing")
                  .foregroundStyle(.secondary)
              }
              Toggle(
                "Always Show Podcast Art for Now Playing",
                isOn: userSettings.$alwaysShowPodcastImageForOnDeck.binding
              )
              .labelsHidden()
            }
            Spacer(minLength: 0)
          }

          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                Maximum number of episodes that can be in your queue. \
                When adding episodes to the end, \
                as many as possible will be added up to the limit. \
                When adding episodes to the beginning, episodes will be removed from the end \
                if necessary to stay within the limit.
                """
            ) {
              HStack {
                Text("Max Queue Length")
                Spacer()
                Text(formattedMaxQueueLength)
                  .foregroundStyle(.secondary)
              }
            }
            Slider(
              value: $tempMaxQueueLength,
              in: 10...100,
              step: 10,
              onEditingChanged: { editing in
                if !editing {
                  userSettings.$maxQueueLength.new(Int(tempMaxQueueLength))
                  Task {
                    do {
                      try await queue.enforceMaxQueueLength()
                    } catch {
                      Self.log.caughtError(
                        "maxQueueLength: enforce failed \(Int(tempMaxQueueLength))",
                        error
                      )
                      guard ErrorKit.isRemarkable(error) else { return }
                      alert(ErrorKit.message(for: error))
                    }
                  }
                }
              }
            )
          }

          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                Number of recommended episodes shown below the queue in Up Next. \
                Set to Off to hide the recommendations section entirely.
                """
            ) {
              HStack {
                Text("Recommended Episodes")
                Spacer()
                Text(formattedMaxRecommendedEpisodes)
                  .foregroundStyle(.secondary)
              }
            }
            Slider(
              value: $tempMaxRecommendedEpisodes,
              in: 0...20,
              step: 1,
              onEditingChanged: { editing in
                if !editing {
                  userSettings.$maxRecommendedEpisodesInUpNext.new(
                    Int(tempMaxRecommendedEpisodes)
                  )
                }
              }
            )
          }

          SettingsRow(
            infoText: """
              When enabled, finishing an episode with an empty queue will automatically \
              play your top recommended episode. Turn off to stop playback at the end of \
              an episode when nothing else is queued.
              """
          ) {
            VStack(alignment: .leading, spacing: 24) {
              Text("Auto-play Recommendation")
              Toggle(
                "Auto-play Recommendation",
                isOn: userSettings.$autoPlayTopRecommendationWhenQueueEmpty.binding
              )
              .labelsHidden()
            }
            Spacer(minLength: 0)
          }
        }

        Section("Storage") {
          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                Maximum size for downloaded episode storage. \
                When the cache reaches this limit, \
                the oldest downloaded episodes will be automatically removed \
                to make space for new downloads. \
                Episodes marked as Saved will never be deleted.
                """
            ) {
              HStack {
                Text("Cache Size Limit")
                Spacer()
                Text(formattedCacheSize)
                  .foregroundStyle(.secondary)
              }
            }
            Slider(
              value: userSettings.$cacheSizeLimitGB.binding,
              in: 0.5...20.0,
              step: 0.5
            )
          }
        }

        if AppInfo.environment.isRelease {
          Section("Feedback") {
            NavigationLink(
              value: Navigation.Destination.settingsSection(.feedback),
              label: { Text("Send Feedback") }
            )
          }
        }

        if AppInfo.environment != .appStore {
          DebugSection()
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            if let url = Self.githubURL {
              Link(destination: url) {
                AppIcon.github.rawLabel
              }
            }
            if let url = Self.discordURL {
              Link(destination: url) {
                AppIcon.discord.rawLabel
              }
            }
            if let url = Self.websiteURL {
              Link(destination: url) {
                AppIcon.website.rawLabel("PodHaven Website")
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
    }
  }
}

#if DEBUG
#Preview {
  SettingsView()
    .preview()
}
#endif
