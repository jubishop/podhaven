// Copyright Justin Bishop, 2025

import FactoryKit
import Sharing
import SwiftUI

struct PodcastSettingsView: View {
  @DynamicInjected(\.userNotificationManager) private var notificationManager
  @DynamicInjected(\.userSettings) private var userSettings

  private let viewModel: PodcastDetailViewModel
  @State private var tempPlayRate: Double
  @State private var tempQueueAllEpisodes: QueueAllEpisodes
  @State private var tempCacheAllEpisodes: CacheAllEpisodes
  @State private var tempNotifyNewEpisodes: Bool

  init(viewModel: PodcastDetailViewModel) {
    self.viewModel = viewModel
    self._tempPlayRate = State(
      initialValue: viewModel.defaultPlaybackRate
        ?? Container.shared.userSettings().defaultPlaybackRate
    )
    self._tempQueueAllEpisodes = State(initialValue: viewModel.queueAllEpisodes)
    self._tempCacheAllEpisodes = State(initialValue: viewModel.cacheAllEpisodes)
    self._tempNotifyNewEpisodes = State(initialValue: viewModel.notifyNewEpisodes)
  }

  var body: some View {
    VStack {
      Text(viewModel.podcast.title)
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)

      Form {
        Section("Playback") {
          VStack(alignment: .trailing, spacing: 24) {
            SettingsRow(
              infoText: """
                Set a custom default playback speed for this podcast.  \
                When enabled, new episodes from this podcast will use this rate \
                instead of the global default.
                """
            ) {
              HStack {
                if viewModel.defaultPlaybackRate != nil {
                  Text("Playback Rate")
                } else {
                  Text("Playback Rate (Unset)")
                }

                Spacer()
                Text(formattedPlaybackRate)
                  .foregroundStyle(.secondary)
              }
            }

            HStack {
              Slider(
                value: $tempPlayRate,
                in: 0.8...2.0,
                step: 0.1,
                onEditingChanged: { editing in
                  if !editing {
                    viewModel.defaultPlaybackRate = tempPlayRate
                  }
                }
              )

              AppIcon.clear
                .imageButton {
                  viewModel.defaultPlaybackRate = nil
                  tempPlayRate = userSettings.defaultPlaybackRate
                }
                .disabled(!viewModel.hasCustomPlayRate)
                .opacity(viewModel.hasCustomPlayRate ? 1.0 : 0.3)
            }
          }
        }

        Section("Queue") {
          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                Automatically add new episodes from this podcast to your queue.  \
                Choose 'Never' to only manually add episodes, \
                'On Bottom' to add them at the end of your queue, \
                or 'On Top' to add them at the beginning.
                """
            ) {
              Text("Queue All Episodes")
            }

            Picker("", selection: $tempQueueAllEpisodes) {
              Text("Never").tag(QueueAllEpisodes.never)
              Text("On Bottom").tag(QueueAllEpisodes.onBottom)
              Text("On Top").tag(QueueAllEpisodes.onTop)
            }
            .pickerStyle(.segmented)
            .onChange(of: tempQueueAllEpisodes) {
              viewModel.queueAllEpisodes = tempQueueAllEpisodes
            }
          }
        }

        Section("Storage") {
          VStack(alignment: .leading, spacing: 24) {
            SettingsRow(
              infoText: """
                Control how episodes from this podcast are cached.  \
                Choose 'Never' to only manually cache episodes, \
                'Cache' to automatically download and cache new episodes, \
                or 'Save' to also prevent cached episodes from being automatically deleted.
                """
            ) {
              Text("Cache All Episodes")
            }

            Picker("", selection: $tempCacheAllEpisodes) {
              Text("Never").tag(CacheAllEpisodes.never)
              Text("Cache").tag(CacheAllEpisodes.cache)
              Text("Save").tag(CacheAllEpisodes.save)
            }
            .pickerStyle(.segmented)
            .onChange(of: tempCacheAllEpisodes) {
              viewModel.cacheAllEpisodes = tempCacheAllEpisodes
            }
          }
        }

        Section("Notifications") {
          SettingsRow(
            infoText: """
              Receive a notification when new episodes are available for this podcast.  \
              Notifications are triggered during background refresh.
              """
          ) {
            Toggle("Notify New Episodes", isOn: $tempNotifyNewEpisodes)
              .onChange(of: tempNotifyNewEpisodes) {
                viewModel.notifyNewEpisodes = tempNotifyNewEpisodes
              }
          }

          if viewModel.notifyNewEpisodes && !notificationManager.isAuthorized {
            if notificationManager.isDenied {
              AppIcon.notificationsDisabled
                .labelButton {
                  AppInfo.openSettings()
                }
                .font(.footnote)
            } else if notificationManager.isNotDetermined {
              AppIcon.notificationsNotDetermined
                .labelButton {
                  Task { await notificationManager.requestAuthorizationIfNeeded() }
                }
                .font(.footnote)
            }
          }
        }
      }
      .task {
        await notificationManager.refreshAuthorizationStatus()
      }
    }
  }

  // MARK: - Private Helpers

  private var formattedPlaybackRate: String {
    "\(tempPlayRate.formatted(decimalPlaces: 1))×"
  }
}

#if DEBUG
#Preview("No Custom Rate") {
  struct PreviewWrapper: View {
    @State private var viewModel: PodcastDetailViewModel?

    var body: some View {
      Group {
        if let viewModel {
          PodcastSettingsView(viewModel: viewModel)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(title: "Sample Podcast")
        viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(podcast))
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper()
}

#Preview("With Custom Default Rate") {
  struct PreviewWrapper: View {
    @State private var viewModel: PodcastDetailViewModel?

    init() {
      Container.shared.userSettings().$defaultPlaybackRate.withLock { $0 = 1.5 }
    }

    var body: some View {
      Group {
        if let viewModel {
          PodcastSettingsView(viewModel: viewModel)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(title: "Sample Podcast")
        viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(podcast))
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper()
}

#Preview("With Podcast Custom Rate") {
  struct PreviewWrapper: View {
    @State private var viewModel: PodcastDetailViewModel?

    var body: some View {
      Group {
        if let viewModel {
          PodcastSettingsView(viewModel: viewModel)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(
          title: "Sample Podcast",
          defaultPlaybackRate: 1.5
        )
        viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(podcast))
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper()
}
#endif
