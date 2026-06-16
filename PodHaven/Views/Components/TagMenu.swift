// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI

// Wrapped as a `View` (not a `@ViewBuilder` helper) so the
// `@DynamicInjected(\.sharedState)` read participates in SwiftUI observation
// — open menus pick up tag renames/adds without an upstream re-render.
@MainActor
struct TagMenu: View {
  @DynamicInjected(\.sharedState) private var sharedState

  let intersection: Set<Tag.ID>
  let union: Set<Tag.ID>
  let onAdd: (Tag.ID) -> Void
  let onRemove: (Tag.ID) -> Void

  init(
    intersection: Set<Tag.ID>,
    union: Set<Tag.ID>,
    onAdd: @escaping (Tag.ID) -> Void,
    onRemove: @escaping (Tag.ID) -> Void
  ) {
    self.intersection = intersection
    self.union = union
    self.onAdd = onAdd
    self.onRemove = onRemove
  }

  init(
    tagIDs: Set<Tag.ID>,
    onAdd: @escaping (Tag.ID) -> Void,
    onRemove: @escaping (Tag.ID) -> Void
  ) {
    self.init(intersection: tagIDs, union: tagIDs, onAdd: onAdd, onRemove: onRemove)
  }

  var body: some View {
    let allTags = sharedState.tags
    let addable = allTags.filter { !intersection.contains($0.id) }
    let removable = allTags.filter { union.contains($0.id) }

    if !addable.isEmpty || !removable.isEmpty {
      Menu {
        if !addable.isEmpty {
          Menu {
            ForEach(addable) { tag in
              Button {
                onAdd(tag.id)
              } label: {
                Label {
                  Text(tag.name)
                } icon: {
                  tag.icon.image
                }
              }
            }
          } label: {
            AppIcon.addTag.label("Add Tag")
          }
        }

        if !removable.isEmpty {
          Menu {
            ForEach(removable) { tag in
              Button {
                onRemove(tag.id)
              } label: {
                Label {
                  Text(tag.name)
                } icon: {
                  tag.icon.image
                }
              }
            }
          } label: {
            AppIcon.removeTag.label("Remove Tag")
          }
        }
      } label: {
        AppIcon.tag.label("Tag")
      }
    }
  }
}
