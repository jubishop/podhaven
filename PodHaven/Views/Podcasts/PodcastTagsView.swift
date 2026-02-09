// Copyright Justin Bishop, 2026

import IdentifiedCollections
import SwiftUI

struct PodcastTagsView: View {
  @Environment(\.colorScheme) private var colorScheme

  let tags: IdentifiedArrayOf<Tag>
  let allTags: [Tag]
  let onAdd: (Tag.ID) -> Void
  let onRemove: (Tag.ID) -> Void

  private var availableTags: [Tag] {
    allTags.filter { tag in
      !tags.contains(where: { $0.id == tag.id })
    }
  }

  var body: some View {
    FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
      ForEach(tags) { tag in
        tagChip(tag)
      }

      if !availableTags.isEmpty {
        addTagMenu
      }
    }
  }

  // MARK: - Components

  private func tagChip(_ tag: Tag) -> some View {
    AppIcon.removeTag
      .labelButton(tag.name) { onRemove(tag.id) }
      .font(.subheadline)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(AppIcon.tag.color(for: colorScheme).opacity(0.15))
      .clipShape(Capsule())
  }

  private var addTagMenu: some View {
    Menu {
      ForEach(availableTags) { tag in
        Button(tag.name) {
          onAdd(tag.id)
        }
      }
    } label: {
      AppIcon.addTag.label
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppIcon.addTag.color(for: colorScheme).opacity(0.15))
        .clipShape(Capsule())
    }
  }
}
