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
          SmartListGroupView(group: $viewModel.topGroup, onRemoveGroup: nil)
        }

        if let nested = viewModel.nested {
          Section("Nested Group") {
            // Binding($viewModel.nested) force-unwraps on reads that can arrive
            // after Remove Group nils the value, trapping mid-update; fall back
            // to the last value while the section disappears.
            SmartListGroupView(
              group: Binding(
                get: { viewModel.nested ?? nested },
                set: { viewModel.nested = $0 }
              )
            ) {
              viewModel.removeNestedGroup()
            }
          }
        } else {
          Section {
            Button("Add Group") { viewModel.addNestedGroup() }
          }
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
        nested: SmartListFilter.Group(
          combinator: .any,
          conditions: [.state(.isLiked), .state(.isLoved)]
        )
      )
    )
  )
  .preview()
}
#endif
