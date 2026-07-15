// Copyright Justin Bishop, 2026

import FactoryKit
import IdentifiedCollections
import SwiftUI

struct TagsSettingsView: View {
  @DynamicInjected(\.sheet) private var sheet

  @State private var viewModel = TagsSettingsViewModel()

  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

  var body: some View {
    List {
      if viewModel.tags.isEmpty {
        Text("No tags yet. Tap + to create one.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.tags) { tag in
          Button {
            sheet(id: "tag-edit-\(tag.id)") {
              TagEditorView(
                viewModel: TagEditorViewModel(
                  mode: .edit(tag.id),
                  name: tag.name,
                  icon: tag.icon,
                  podcastCount: viewModel.podcastCounts[tag.id] ?? 0,
                  episodeCount: viewModel.episodeCounts[tag.id] ?? 0
                )
              )
            }
          } label: {
            tagRow(tag)
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .trailing) {
            AppIcon.delete
              .imageButton {
                viewModel.deleteTag(tag.id)
              }
              .accessibilityLabel("Delete Tag")
          }
        }
      }
    }
    .navigationTitle("Tags")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        AppIcon.addTag.labelButton {
          sheet(id: "tag-create") {
            TagEditorView(viewModel: TagEditorViewModel(mode: .create))
          }
        }
      }
    }
    .task(viewModel.execute)
  }

  private func tagRow(_ tag: Tag) -> some View {
    HStack(spacing: 12) {
      LucideIconView(icon: tag.icon)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
      VStack(alignment: .leading) {
        Text(tag.name)
        Text(
          """
          Podcasts: \(viewModel.podcastCounts[tag.id] ?? 0) · Episodes: \
          \(viewModel.episodeCounts[tag.id] ?? 0)
          """
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .contentShape(Rectangle())
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    TagsSettingsView()
  }
  .preview()
}
#endif
