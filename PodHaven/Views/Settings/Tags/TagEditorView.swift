// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI

struct TagEditorView: View {
  @DynamicInjected(\.sheet) private var sheet

  @State private var viewModel: TagEditorViewModel

  @FocusState private var nameFocused: Bool

  init(viewModel: TagEditorViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $viewModel.name)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit { viewModel.save() }

          NavigationLink {
            IconPickerView(selection: $viewModel.icon)
          } label: {
            LabeledContent("Icon") {
              LucideIconView(icon: viewModel.icon)
                .frame(width: 24, height: 24)
                .foregroundStyle(.tint)
            }
          }
        }
      }
      .navigationTitle("Edit Tag")
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
    }
  }
}
