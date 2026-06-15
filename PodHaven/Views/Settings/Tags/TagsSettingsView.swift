// Copyright Justin Bishop, 2026

import FactoryKit
import IdentifiedCollections
import SwiftUI

struct TagsSettingsView: View {
  @DynamicInjected(\.sheet) private var sheet

  @State private var viewModel = TagsSettingsViewModel()

  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

  var body: some View {
    List {
      if viewModel.tags.isEmpty {
        Text("No tags yet")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.tags) { tag in
          Button {
            sheet(id: "tag-edit-\(tag.id)") {
              TagEditorView(viewModel: TagEditorViewModel(tag: tag))
            }
          } label: {
            tagRow(tag)
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .trailing) {
            AppIcon.delete.imageButton {
              viewModel.deleteTag(tag.id)
            }
          }
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 12) {
      addBar
    }
    .navigationTitle("Tags")
    .task(viewModel.execute)
  }

  private func tagRow(_ tag: Tag) -> some View {
    HStack(spacing: 12) {
      LucideIconView(icon: tag.icon)
        .frame(width: iconSize, height: iconSize)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
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
      Spacer()
    }
    .contentShape(Rectangle())
  }

  private var addBar: some View {
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
}

#if DEBUG
#Preview {
  NavigationStack {
    TagsSettingsView()
  }
  .preview()
}
#endif
