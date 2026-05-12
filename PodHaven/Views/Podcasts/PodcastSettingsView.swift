// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct PodcastSettingsView: View {
  @DynamicInjected(\.userNotificationManager) private var notificationManager
  @DynamicInjected(\.userSettings) private var userSettings

  private let viewModel: PodcastDetailViewModel
  @State private var temp: PodcastSettings

  init(viewModel: PodcastDetailViewModel, settings: PodcastSettings) {
    self.viewModel = viewModel
    self._temp = State(initialValue: settings)
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
                if temp.defaultPlaybackRate != nil {
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
                value: Binding(
                  get: { temp.defaultPlaybackRate ?? userSettings.defaultPlaybackRate },
                  set: { temp.defaultPlaybackRate = $0 }
                ),
                in: 0.8...2.0,
                step: 0.1,
                onEditingChanged: { editing in
                  if !editing {
                    viewModel.updateSettings(temp)
                  }
                }
              )

              AppIcon.clear
                .imageButton {
                  temp.defaultPlaybackRate = nil
                  viewModel.updateSettings(temp)
                }
                .disabled(temp.defaultPlaybackRate == nil)
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

            Picker("", selection: $temp.queueAllEpisodes) {
              Text("Never").tag(QueueAllEpisodes.never)
              Text("On Bottom").tag(QueueAllEpisodes.onBottom)
              Text("On Top").tag(QueueAllEpisodes.onTop)
            }
            .pickerStyle(.segmented)
            .onChange(of: temp.queueAllEpisodes) {
              viewModel.updateSettings(temp)
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

            Picker("", selection: $temp.cacheAllEpisodes) {
              Text("Never").tag(CacheAllEpisodes.never)
              Text("Cache").tag(CacheAllEpisodes.cache)
              Text("Save").tag(CacheAllEpisodes.save)
            }
            .pickerStyle(.segmented)
            .onChange(of: temp.cacheAllEpisodes) {
              viewModel.updateSettings(temp)
            }
          }
        }

        Section("Recommendations") {
          VStack(alignment: .leading, spacing: 16) {
            SettingsRow(
              infoText: """
                How quickly older episodes from this podcast lose their freshness boost in \
                recommendations, expressed as the show's natural publish cadence.  Auto \
                detects the cadence from the feed's publish dates and tracks it as new \
                episodes arrive.  Daily for news-style shows, Weekly for most podcasts, \
                Monthly for less time-sensitive shows, and Evergreen for back-catalog or \
                narrative-archive content where episode age is immaterial.
                """
            ) {
              HStack(alignment: .firstTextBaseline) {
                Text("Freshness")
                Spacer()
                Picker("", selection: $temp.freshnessCadence) {
                  Text("Auto").tag(FreshnessCadence?.none)
                  Text("Daily").tag(FreshnessCadence?.some(.daily))
                  Text("Weekly").tag(FreshnessCadence?.some(.weekly))
                  Text("Monthly").tag(FreshnessCadence?.some(.monthly))
                  Text("Evergreen").tag(FreshnessCadence?.some(.evergreen))
                }
                .pickerStyle(.menu)
                .onChange(of: temp.freshnessCadence) {
                  viewModel.updateSettings(temp)
                }
              }
            }

            if temp.freshnessCadence == nil {
              Text("Resolved to \(viewModel.inferredFreshnessCadence.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Toggle("Notify New Episodes", isOn: $temp.notifyNewEpisodes)
              .onChange(of: temp.notifyNewEpisodes) {
                viewModel.updateSettings(temp)
              }
          }

          if temp.notifyNewEpisodes && !notificationManager.isAuthorized {
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
    let rate = temp.defaultPlaybackRate ?? userSettings.defaultPlaybackRate
    return "\(rate.formatted(decimalPlaces: 1))×"
  }
}

#if DEBUG
#Preview("No Custom Rate") {
  struct PreviewWrapper: View {
    @State private var settings: PodcastSettings?
    @State private var viewModel: PodcastDetailViewModel?

    var body: some View {
      Group {
        if let viewModel, let settings {
          PodcastSettingsView(viewModel: viewModel, settings: settings)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(title: "Sample Podcast")
        let displayed = DisplayedPodcast(podcast)
        settings = displayed.settings
        viewModel = PodcastDetailViewModel(podcast: displayed)
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper().preview()
}

#Preview("With Custom Default Rate") {
  struct PreviewWrapper: View {
    @State private var settings: PodcastSettings?
    @State private var viewModel: PodcastDetailViewModel?

    init() {
      Container.shared.userSettings().$defaultPlaybackRate.new(1.5)
    }

    var body: some View {
      Group {
        if let viewModel, let settings {
          PodcastSettingsView(viewModel: viewModel, settings: settings)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(title: "Sample Podcast")
        let displayed = DisplayedPodcast(podcast)
        settings = displayed.settings
        viewModel = PodcastDetailViewModel(podcast: displayed)
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper().preview()
}

#Preview("With Podcast Custom Rate") {
  struct PreviewWrapper: View {
    @State private var settings: PodcastSettings?
    @State private var viewModel: PodcastDetailViewModel?

    var body: some View {
      Group {
        if let viewModel, let settings {
          PodcastSettingsView(viewModel: viewModel, settings: settings)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(
          title: "Sample Podcast",
          defaultPlaybackRate: 1.5
        )
        let displayed = DisplayedPodcast(podcast)
        settings = displayed.settings
        viewModel = PodcastDetailViewModel(podcast: displayed)
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper().preview()
}

#Preview("Daily Freshness Cadence") {
  struct PreviewWrapper: View {
    @State private var settings: PodcastSettings?
    @State private var viewModel: PodcastDetailViewModel?

    var body: some View {
      Group {
        if let viewModel, let settings {
          PodcastSettingsView(viewModel: viewModel, settings: settings)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(
          title: "Daily News",
          freshnessCadence: .daily
        )
        let displayed = DisplayedPodcast(podcast)
        settings = displayed.settings
        viewModel = PodcastDetailViewModel(podcast: displayed)
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper().preview()
}

#Preview("Evergreen Freshness Cadence") {
  struct PreviewWrapper: View {
    @State private var settings: PodcastSettings?
    @State private var viewModel: PodcastDetailViewModel?

    var body: some View {
      Group {
        if let viewModel, let settings {
          PodcastSettingsView(viewModel: viewModel, settings: settings)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(
          title: "Hardcore History",
          freshnessCadence: .evergreen
        )
        let displayed = DisplayedPodcast(podcast)
        settings = displayed.settings
        viewModel = PodcastDetailViewModel(podcast: displayed)
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper().preview()
}

#Preview("Auto Freshness Cadence") {
  struct PreviewWrapper: View {
    @State private var settings: PodcastSettings?
    @State private var viewModel: PodcastDetailViewModel?

    var body: some View {
      Group {
        if let viewModel, let settings {
          PodcastSettingsView(viewModel: viewModel, settings: settings)
        } else {
          ProgressView()
        }
      }
      .task {
        let podcast = try! await Create.podcast(title: "Auto Cadence Sample")
        let displayed = DisplayedPodcast(podcast)
        settings = displayed.settings
        viewModel = PodcastDetailViewModel(podcast: displayed)
        viewModel?.appear()
      }
    }
  }

  return PreviewWrapper().preview()
}
#endif
