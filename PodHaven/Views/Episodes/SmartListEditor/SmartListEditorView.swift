// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI
import Tagged

struct SmartListEditorView: View {
  @DynamicInjected(\.sheet) private var sheet

  @State private var viewModel: SmartListEditorViewModel
  @State private var confirmingDelete = false

  init(viewModel: SmartListEditorViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Title", text: $viewModel.title)
        }

        Section("Conditions") {
          Picker("Match", selection: $viewModel.topGroup.combinator) {
            Text("All").tag(SmartListFilter.Combinator.all)
            Text("Any").tag(SmartListFilter.Combinator.any)
          }
          .pickerStyle(.segmented)

          ForEach($viewModel.topGroup.conditions) { $condition in
            SmartListConditionRow(condition: $condition) {
              viewModel.topGroup.conditions.removeAll { $0.id == condition.id }
            }
          }

          ForEach($viewModel.groups) { $group in
            SmartListGroupView(group: $group) {
              viewModel.removeGroup(group.id)
            }
          }

          Button("Add Condition") {
            viewModel.topGroup.conditions.append(EditableCondition())
          }
          Button("Add Group") { viewModel.addGroup() }
        }

        if let message = viewModel.validationMessage {
          Section {
            Text(message)
              .foregroundStyle(.red)
          }
        } else if viewModel.matchesAllEpisodes {
          Section {
            Text("This list will match every episode.")
              .foregroundStyle(.secondary)
          }
        }

        if case .edit = viewModel.mode {
          Section {
            Button("Delete Smart List", role: .destructive) { confirmingDelete = true }
          }
        }
      }
      .navigationTitle(viewModel.mode == .create ? "New Smart List" : "Edit Smart List")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { sheet.dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { viewModel.save() }
            .disabled(!viewModel.canSave)
        }
      }
      .confirmationDialog(
        "Delete this Smart List?",
        isPresented: $confirmingDelete,
        titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive) { viewModel.delete() }
      }
    }
  }
}

#if DEBUG
#Preview("Create") {
  SmartListEditorView(viewModel: SmartListEditorViewModel(mode: .create))
    .preview()
}

#Preview("Edit") {
  SmartListEditorView(
    viewModel: SmartListEditorViewModel(
      mode: .edit(SmartList.ID(1)),
      title: "Quick Tech Hits",
      filter: SmartListFilter(
        combinator: .all,
        conditions: [
          .podcastText(.title, .contains, "Tech"),
          .duration(minSeconds: nil, maxSeconds: 1800),
          .publishDate(.withinLast, days: 7),
        ],
        groups: [
          SmartListFilter.Group(
            combinator: .any,
            conditions: [.state(.isLiked), .state(.isLoved)]
          ),
          SmartListFilter.Group(
            combinator: .any,
            conditions: [.state(.isCached), .state(.isSaved)]
          ),
        ]
      )
    )
  )
  .preview()
}
#endif
