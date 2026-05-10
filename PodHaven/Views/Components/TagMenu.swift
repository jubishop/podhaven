// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI

// Shared filtered Add Tag / Remove Tag submenu used by both per-row context
// menus and bulk multi-select toolbars.
//
// Add Tag → only tags missing from `intersection` (tags every target shares).
// Remove Tag → only tags present in `union` (tags any target has).
// For per-row callers, intersection == union == the row's own tag IDs.
//
// Wrapped as a struct view (rather than a `@ViewBuilder` helper) so
// `@DynamicInjected(\.sharedState)` participates in SwiftUI observation
// tracking — tag renames/adds reflect in the open menu without waiting for
// some unrelated re-render upstream.
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
              Button(tag.name) { onAdd(tag.id) }
            }
          } label: {
            AppIcon.addTag.label("Add Tag")
          }
        }

        if !removable.isEmpty {
          Menu {
            ForEach(removable) { tag in
              Button(tag.name) { onRemove(tag.id) }
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
