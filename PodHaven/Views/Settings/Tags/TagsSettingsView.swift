// Copyright Justin Bishop, 2026

import IdentifiedCollections
import SwiftUI

struct TagsSettingsView: View {
  @State private var viewModel = TagsSettingsViewModel()

  var body: some View {
    List {
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
    .safeAreaInset(edge: .top, spacing: 12) {
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
      .padding()
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
      .padding(.horizontal)
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
