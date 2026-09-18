// Copyright Justin Bishop, 2026

#if DEBUG
import SwiftUI

private struct CarPlayPodcastPreview: View {
  enum Content { case recent, all, unfinished, finished, loading, empty, failed, restricted }
  let content: Content

  var body: some View {
    List {
      switch content {
      case .recent:
        Button("All Podcasts") {}
        Section("Recently Updated") {
          row("Example podcast", "12 saved episodes · Sep 17, 2026")
          row("Another podcast", "8 saved episodes · Sep 16, 2026")
        }
      case .all:
        row("Another podcast", "8 saved episodes")
        row("Empty podcast", "No saved episodes")
        row("Example podcast", "12 saved episodes")
        Button("Next page") {}
      case .unfinished, .finished:
        Button(content == .unfinished ? "All Episodes" : "Unfinished") {}
        Section(
          content == .unfinished ? "Example podcast · Unfinished" : "Example podcast · All Episodes"
        ) {
          row(
            "An episode in progress",
            "Example podcast · 24m remaining · In progress · Downloaded"
          )
          ProgressView(value: 0.4).accessibilityLabel("Episode progress")
          row("An unplayed episode", "Example podcast · 40m · Not started")
          if content == .finished { row("A finished episode", "Example podcast · Finished") }
        }
      case .loading:
        ContentUnavailableView(
          "Loading podcasts…",
          systemImage: AppIcon.podcasts.systemImageName,
          description: Text("Reading saved subscriptions.")
        )
      case .empty:
        Button("All Episodes") {}
        row("No saved episodes", "Only saved episodes appear here.")
      case .failed:
        Button("Retry") {}
        Text("Couldn't load episodes.")
      case .restricted:
        Button("All Podcasts") {}
        row(
          "Example podcast",
          "12 saved episodes · More podcasts available when vehicle limits permit."
        )
      }
    }
  }

  private func row(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading) {
      Text(title)
      Text(detail).font(.caption)
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview("CarPlay recent podcasts") { CarPlayPodcastPreview(content: .recent) }
#Preview("CarPlay all podcasts") { CarPlayPodcastPreview(content: .all) }
#Preview("CarPlay unfinished episodes") { CarPlayPodcastPreview(content: .unfinished) }
#Preview("CarPlay all saved episodes") { CarPlayPodcastPreview(content: .finished) }
#Preview("CarPlay podcast loading") { CarPlayPodcastPreview(content: .loading) }
#Preview("CarPlay no saved episodes") { CarPlayPodcastPreview(content: .empty) }
#Preview("CarPlay podcast failure") { CarPlayPodcastPreview(content: .failed) }
#Preview("CarPlay restricted podcasts") { CarPlayPodcastPreview(content: .restricted) }
#endif
