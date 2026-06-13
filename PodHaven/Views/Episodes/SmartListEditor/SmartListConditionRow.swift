// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI

struct SmartListConditionRow: View {
  @DynamicInjected(\.sharedState) private var sharedState

  @Binding var condition: EditableCondition
  let onRemove: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        AppIcon.removeSmartListCondition.imageButton(action: onRemove)
          .buttonStyle(.borderless)
        Picker("Condition", selection: $condition.kind) {
          ForEach(EditableCondition.Kind.allCases, id: \.self) { kind in
            Text(kind.label).tag(kind)
          }
        }
        .labelsHidden()
        Spacer()
      }

      detailControls

      if let message = condition.validationMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  @ViewBuilder
  private var detailControls: some View {
    switch condition.kind {
    case .episodeTitle, .episodeDescription, .podcastTitle, .podcastDescription:
      HStack {
        Picker("Operator", selection: $condition.textOp) {
          ForEach(SmartListFilter.TextOp.allCases, id: \.self) { textOp in
            Text(textOp.label).tag(textOp)
          }
        }
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        TextField("Text", text: $condition.text)
      }
    case .state:
      Picker("State", selection: $condition.state) {
        ForEach(SmartListFilter.StateCondition.allCases, id: \.self) { state in
          Text(state.label).tag(state)
        }
      }
      .labelsHidden()
    case .episodeTag, .podcastTag:
      HStack {
        Picker("Membership", selection: $condition.tagMembership) {
          ForEach(EditableCondition.TagMembership.allCases, id: \.self) { membership in
            Text(membership.label).tag(membership)
          }
        }
        .labelsHidden()
        if condition.tagMembership == .hasTag || condition.tagMembership == .doesNotHaveTag {
          Picker("Tag", selection: $condition.tagID) {
            Text("Select a tag").tag(Tag.ID?.none)
            ForEach(sharedState.tags) { tag in
              Text(tag.name).tag(Tag.ID?.some(tag.id))
            }
          }
          .labelsHidden()
        }
      }
    case .duration:
      HStack {
        TextField("Min", text: $condition.minMinutesText)
          .keyboardType(.numberPad)
        Text("to")
          .foregroundStyle(.secondary)
        TextField("Max", text: $condition.maxMinutesText)
          .keyboardType(.numberPad)
        Text("minutes")
          .foregroundStyle(.secondary)
      }
    case .publishDate:
      HStack {
        Picker("When", selection: $condition.publishDateOp) {
          ForEach(SmartListFilter.PublishDateOp.allCases, id: \.self) { publishDateOp in
            Text(publishDateOp.label).tag(publishDateOp)
          }
        }
        .labelsHidden()
        TextField("Days", text: $condition.daysText)
          .keyboardType(.numberPad)
        Text("days")
          .foregroundStyle(.secondary)
      }
    }
  }
}

// MARK: - Labels

extension SmartListFilter.TextOp {
  fileprivate var label: String {
    switch self {
    case .contains: return "contains"
    case .doesNotContain: return "exclude"
    case .equals: return "equals"
    }
  }
}

extension SmartListFilter.PublishDateOp {
  fileprivate var label: String {
    switch self {
    case .withinLast: return "within last"
    case .olderThan: return "older than"
    }
  }
}

extension SmartListFilter.StateCondition {
  fileprivate var label: String {
    switch self {
    case .isQueued: return "Queued"
    case .isUnqueued: return "Unqueued"
    case .isFinished: return "Finished"
    case .isUnfinished: return "Unfinished"
    case .isStarted: return "Started"
    case .isUnstarted: return "Unstarted"
    case .isCached: return "Cached"
    case .isSaved: return "Saved"
    case .isLoved: return "Loved"
    case .isLiked: return "Liked"
    case .isDisliked: return "Disliked"
    case .isNotInterested: return "Not Interested"
    case .isRated: return "Rated"
    case .isUnrated: return "Unrated"
    case .wasPreviouslyQueued: return "Previously Queued"
    }
  }
}
