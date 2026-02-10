// Copyright Justin Bishop, 2026

import FactoryKit
import IdentifiedCollections
import SwiftUI

struct TagsView: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation

  let tags: IdentifiedArrayOf<Tag>
  let allTags: IdentifiedArrayOf<Tag>
  let onAdd: (Tag.ID) -> Void
  let onRemove: (Tag.ID) -> Void

  private var availableTags: IdentifiedArrayOf<Tag> {
    allTags.filter { !tags.ids.contains($0.id) }
  }

  var body: some View {
    FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
      ForEach(tags) { tag in
        tagChip(tag)
      }

      addTagMenu
    }
  }

  // MARK: - Components

  private func tagChip(_ tag: Tag) -> some View {
    Button {
      onRemove(tag.id)
    } label: {
      HStack(spacing: 4) {
        AppIcon.removeTag.image
        Text(tag.name)
      }
    }
    .tint(.accentColor)
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

      if !availableTags.isEmpty {
        Divider()
      }

      AppIcon.manageTags.labelButton {
        navigation.showTagsSettings()
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
