// Copyright Justin Bishop, 2026

import IdentifiedCollections
import SwiftUI

struct TagsSettingsView: View {
  @FocusState private var focusedTagID: Tag.ID?
  @State private var viewModel = TagsSettingsViewModel()

  var body: some View {
    List {
      if viewModel.tags.isEmpty {
        Text("No tags yet")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.tags) { tag in
          if viewModel.editingTagID == tag.id {
            TextField("Tag name", text: $viewModel.editingTagName)
              .textInputAutocapitalization(.words)
              .submitLabel(.done)
              .focused($focusedTagID, equals: tag.id)
              .onSubmit(viewModel.renameTag)
              .onAppear { focusedTagID = tag.id }
          } else {
            VStack(alignment: .leading) {
              Text(tag.name)
              Text(
                """
                Podcasts: \(viewModel.podcastCounts[tag.id] ?? 0) · Episodes: \
                \(viewModel.episodeCounts[tag.id] ?? 0)
                """
              )
              .font(.subheadline)
              .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.startEditing(tag) }
            .swipeActions(edge: .trailing) {
              AppIcon.removeTag.imageButton {
                viewModel.deleteTag(tag.id)
              }
            }
          }
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 12) {
      HStack {
        TextField("New tag name", text: $viewModel.newTagName)
          .textInputAutocapitalization(.words)
          .submitLabel(.done)
          .onSubmit(viewModel.addTag)

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
    .task(viewModel.execute)
    .onChange(of: focusedTagID) { _, newValue in
      if newValue == nil, viewModel.editingTagID != nil {
        viewModel.renameTag()
      }
    }
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
