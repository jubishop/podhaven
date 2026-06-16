// Copyright Justin Bishop, 2026

import FactoryKit
import SwiftUI

struct TagEditorView: View {
  @DynamicInjected(\.sheet) private var sheet

  @State private var viewModel: TagEditorViewModel

  @FocusState private var nameFocused: Bool

  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

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
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.primary)
            }
          }
        }

        if case .edit = viewModel.mode {
          Section {
            Button(role: .destructive) {
              viewModel.deleteTag()
            } label: {
              Text("Delete Tag")
                .frame(maxWidth: .infinity, alignment: .center)
            }
          }
        }
      }
      .navigationTitle(viewModel.mode == .create ? "New Tag" : "Edit Tag")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        if viewModel.mode == .create {
          nameFocused = true
        }
      }
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
