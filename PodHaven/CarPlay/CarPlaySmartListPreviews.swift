// Copyright Justin Bishop, 2026

#if DEBUG
import SwiftUI

private struct CarPlaySmartListPreview: View {
  enum Content { case hub, episodes, loading, noLists, empty, failed, fallback, restricted }
  let content: Content

  var body: some View {
    List {
      switch content {
      case .hub:
        Label {
          Text("Recent Episodes · 12 unread")
        } icon: {
          LucideIcon.listMusic.image.accessibilityHidden(true)
        }
        Label {
          Text("Saved")
        } icon: {
          LucideIcon.heart.image.accessibilityHidden(true)
        }
        Button("Next page") {}
      case .episodes, .fallback:
        Section(content == .fallback ? "Recent · Ranking unavailable; newest first" : "Recent") {
          VStack(alignment: .leading) {
            Text("A saved episode")
            Text("Example podcast · 24m remaining · Current episode · Downloaded").font(.caption)
            ProgressView(value: 0.4).accessibilityLabel("Episode progress")
          }
          .accessibilityElement(children: .combine)
          Text("Another episode")
        }
        Button("Next page") {}
      case .loading:
        ProgressView("Loading Smart Lists…")
      case .noLists:
        ContentUnavailableView(
          "No Smart Lists",
          systemImage: AppIcon.episodes.systemImageName,
          description: Text("Your saved Smart Lists appear here.")
        )
      case .empty:
        ContentUnavailableView(
          "No matching episodes",
          systemImage: AppIcon.episodes.systemImageName,
          description: Text("Recent Episodes")
        )
      case .failed:
        Button("Retry") {}
        Text("Couldn't load episodes.")
      case .restricted:
        Text("Recent Episodes")
        Text("More Smart Lists available when vehicle limits permit.").font(.caption)
      }
    }
  }
}

#Preview("CarPlay Smart Lists") { CarPlaySmartListPreview(content: .hub) }
#Preview("CarPlay Smart List episodes") { CarPlaySmartListPreview(content: .episodes) }
#Preview("CarPlay loading Smart Lists") { CarPlaySmartListPreview(content: .loading) }
#Preview("CarPlay no Smart Lists") { CarPlaySmartListPreview(content: .noLists) }
#Preview("CarPlay empty Smart List") { CarPlaySmartListPreview(content: .empty) }
#Preview("CarPlay Smart List retry") { CarPlaySmartListPreview(content: .failed) }
#Preview("CarPlay ranking unavailable") { CarPlaySmartListPreview(content: .fallback) }
#Preview("CarPlay restricted Smart Lists") { CarPlaySmartListPreview(content: .restricted) }
#endif
