// Copyright Justin Bishop, 2025

import FactoryKit
import Sharing
import SwiftUI

struct SettingsView: View {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.userSettings) private var userSettings

  private static let log = Log.as(LogSubsystem.SettingsView.main)
  private static let githubURL = URL(string: "https://github.com/jubishop/podhaven")

  @State private var tempMaxQueueLength: Double

  private let viewModel = SettingsViewModel()

  init() {
    self._tempMaxQueueLength = State(
      initialValue: Double(Container.shared.userSettings().maxQueueLength)
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

  var body: some View {
    NavStack(manager: navigation.settings) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(
            value: Navigation.Destination.settingsSection(.opml),
            label: { Text("OPML") }
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
              value: Binding(userSettings.$defaultPlaybackRate),
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
                or "Skip Interval" to jump forward using your custom skip interval \
                (also enables Previous Track for jumping back).
                """
            ) {
              Text("Next Track Behavior")
              Spacer()
            }

            Picker("Next Track Behavior", selection: Binding(userSettings.$nextTrackBehavior)) {
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

            Picker("Skip Forward Interval", selection: Binding(userSettings.$skipForwardInterval)) {
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

            Picker("Skip Backward Interval", selection: Binding(userSettings.$skipBackwardInterval))
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
            Toggle("Enable Undo Seek", isOn: Binding(userSettings.$enableUndoSeek))
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
            }

            Picker("", selection: Binding(userSettings.$appearanceMode)) {
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
            Toggle("Shrink Playbar", isOn: Binding(userSettings.$shrinkPlayBarOnScroll))
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
              isOn: Binding(userSettings.$showTimeRemainingInEpisodeLists)
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
            Toggle("Show Now Playing", isOn: Binding(userSettings.$showNowPlayingInUpNext))
          }

          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                When enabled, \
                episodes in the Up Next queue will always display the podcast artwork \
                instead of the episode-specific artwork.
                """
            ) {
              Text("Always Show Podcast Art")
              Spacer()
            }
            Toggle(
              "Always Show Podcast Art",
              isOn: Binding(userSettings.$alwaysShowPodcastImageInUpNext)
            )
            .labelsHidden()
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
              in: 50...500,
              step: 50,
              onEditingChanged: { editing in
                if !editing {
                  userSettings.$maxQueueLength.withLock { $0 = Int(tempMaxQueueLength) }
                  Task {
                    do {
                      try await queue.enforceMaxQueueLength()
                    } catch {
                      Self.log.error(error)
                    }
                  }
                }
              }
            )
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
              value: Binding(userSettings.$cacheSizeLimitGB),
              in: 0.5...20.0,
              step: 0.5
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
                Label {
                  Text("GitHub")
                } icon: {
                  Image("github-mark")
                }
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
