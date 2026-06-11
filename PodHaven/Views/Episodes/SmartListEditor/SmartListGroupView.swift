// Copyright Justin Bishop, 2026

import SwiftUI

// Renders one filter group: a combinator toggle, its condition rows, and an
// add button. Deliberately non-recursive — the editor shows at most the top
// group plus one nested group.
struct SmartListGroupView: View {
  @Binding var group: EditableGroup
  let onRemoveGroup: (() -> Void)?

  var body: some View {
    Picker("Match", selection: $group.combinator) {
      Text("All").tag(SmartListFilter.Combinator.all)
      Text("Any").tag(SmartListFilter.Combinator.any)
    }
    .pickerStyle(.segmented)

    ForEach($group.conditions) { $condition in
      SmartListConditionRow(condition: $condition) {
        group.conditions.removeAll { $0.id == condition.id }
      }
    }

    Button("Add Condition") {
      group.conditions.append(EditableCondition())
    }

    if let onRemoveGroup {
      Button("Remove Group", role: .destructive, action: onRemoveGroup)
    }
  }
}
