// Copyright Justin Bishop, 2026

import SwiftUI

struct TagsSettingsView: View {
  @State private var viewModel = TagsSettingsViewModel()

  var body: some View {
    Form {
      Section {
        HStack {
          TextField("New tag name", text: $viewModel.newTagName)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit { viewModel.addTag() }

          AppIcon.addTag
            .imageButton(action: viewModel.addTag)
            .disabled(
              viewModel.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
      }

      Section("All Tags") {
        if viewModel.tags.isEmpty {
          Text("No tags yet")
            .foregroundStyle(.secondary)
        } else {
          ForEach(viewModel.tags) { tag in
            Text(tag.name)
          }
          .onDelete { indexSet in
            for index in indexSet {
              viewModel.deleteTag(viewModel.tags[index].id)
            }
          }
        }
      }
    }
    .navigationTitle("Tags")
    .onAppear { viewModel.loadTags() }
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    TagsSettingsView()
  }
  .preview()
}
#endif
