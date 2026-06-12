// Copyright Justin Bishop, 2026

import SwiftUI

// Renders one nested group inline in the top group's condition list: a header
// row with a remove button and combinator toggle, then the group's condition
// rows and add button indented so the group reads as a single term of the
// outer Any/All. Deliberately non-recursive — groups hold only conditions.
struct SmartListGroupView: View {
  @Binding var group: EditableGroup
  let onRemove: @MainActor @Sendable () -> Void

  var body: some View {
    HStack {
      AppIcon.removeSmartListGroup.imageButton(action: onRemove)
        .buttonStyle(.borderless)
      Picker("Match", selection: $group.combinator) {
        Text("All").tag(SmartListFilter.Combinator.all)
        Text("Any").tag(SmartListFilter.Combinator.any)
      }
      .pickerStyle(.segmented)
    }

    ForEach($group.conditions) { $condition in
      SmartListConditionRow(condition: $condition) {
        group.conditions.removeAll { $0.id == condition.id }
      }
      .padding(.leading)
    }

    Button("Add Condition") {
      group.conditions.append(EditableCondition())
    }
    .padding(.leading)
  }
}
