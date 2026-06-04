// Copyright Justin Bishop, 2026

import FactoryKit
import IdentifiedCollections
import SwiftUI

// Wrapped as Views (not @ViewBuilder helpers) so the @DynamicInjected reads
// participate in SwiftUI observation — the label and tag submenu pick up
// setting changes and tag renames/adds without an upstream re-render.

@MainActor
struct CommandCenterLikeMenu: View {
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings

  var body: some View {
    let action = userSettings.commandCenterLikeAction
    let tags = sharedState.tags
    Menu {
      AppIcon.loveEpisode.labelButton("Love") {
        userSettings.$commandCenterLikeAction.new(.love)
      }
      AppIcon.likeEpisode.labelButton("Like") {
        userSettings.$commandCenterLikeAction.new(.like)
      }
      AppIcon.saveEpisodeInCache.labelButton("Save in Cache") {
        userSettings.$commandCenterLikeAction.new(.saveInCache)
      }
      commandCenterTagSubmenu(tags: tags) { tagID in
        userSettings.$commandCenterLikeAction.new(.addTag(tagID))
      }
    } label: {
      switch action {
      case .love: AppIcon.loveEpisode.label(action.title(tags: tags))
      case .like: AppIcon.likeEpisode.label(action.title(tags: tags))
      case .saveInCache: AppIcon.saveEpisodeInCache.label(action.title(tags: tags))
      case .addTag: AppIcon.tag.label(action.title(tags: tags))
      }
    }
  }
}

@MainActor
struct CommandCenterDislikeMenu: View {
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings

  var body: some View {
    let action = userSettings.commandCenterDislikeAction
    let tags = sharedState.tags
    Menu {
      AppIcon.dislikeEpisode.labelButton("Dislike") {
        userSettings.$commandCenterDislikeAction.new(.dislike)
      }
      commandCenterTagSubmenu(tags: tags) { tagID in
        userSettings.$commandCenterDislikeAction.new(.addTag(tagID))
      }
    } label: {
      switch action {
      case .dislike: AppIcon.dislikeEpisode.label(action.title(tags: tags))
      case .addTag: AppIcon.tag.label(action.title(tags: tags))
      }
    }
  }
}

// Shared "Add Tag" submenu listing every tag; hidden when none exist so the
// option never appears without targets, matching the rest of the tag UI.
@MainActor @ViewBuilder
private func commandCenterTagSubmenu(
  tags: IdentifiedArrayOf<Tag>,
  select: @escaping (Tag.ID) -> Void
) -> some View {
  if !tags.isEmpty {
    Menu {
      ForEach(tags) { tag in
        Button(tag.name) { select(tag.id) }
      }
    } label: {
      AppIcon.addTag.label("Add Tag")
    }
  }
}
