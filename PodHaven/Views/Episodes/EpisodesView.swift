// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct EpisodesView: View {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.sheet) private var sheet

  @State private var viewModel = EpisodesViewModel()

  var body: some View {
    NavStack(manager: navigation.episodes) {
      content
        .navigationTitle("Episodes")
        .toolbar { toolbar }
        .task(viewModel.observeSmartLists)
        .task(viewModel.observeUnreadCounts)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.loadingState {
    case .loading:
      VStack {
        ProgressView("Loading Smart Lists…")
          .foregroundColor(.secondary)
          .padding()
        Spacer()
      }
    case .loaded:
      if viewModel.smartLists.isEmpty {
        emptyState
      } else {
        smartListsView
      }
    case .failed:
      VStack {
        Text("Couldn't load Smart Lists.")
          .foregroundColor(.secondary)
          .padding()
        Spacer()
      }
    }
  }

  private var smartListsView: some View {
    List {
      ForEach(viewModel.smartLists) { smartList in
        NavigationLink(value: Navigation.Destination.smartList(smartList.id)) {
          LabeledContent {
            UnreadBadge(count: viewModel.unreadCounts[smartList.id, default: 0])
          } label: {
            LucideLabel(icon: smartList.icon, title: smartList.title)
          }
        }
        .swipeActions(edge: .leading) {
          AppIcon.settings.imageButton {
            sheet(id: "smart-list-editor-\(smartList.id)") {
              SmartListEditorView(
                viewModel: SmartListEditorViewModel(
                  mode: .edit(smartList.id),
                  title: smartList.title,
                  filter: smartList.filter,
                  alwaysShowPodcastImage: smartList.alwaysShowPodcastImage,
                  icon: smartList.icon
                )
              )
            }
          }
        }
        .swipeActions(edge: .trailing) {
          AppIcon.delete.imageButton {
            viewModel.deleteSmartList(smartList)
          }
        }
      }
      .onMove(perform: viewModel.moveSmartList)
      .onDelete(perform: viewModel.deleteSmartList(at:))
    }
    .environment(\.editMode, $viewModel.editMode)
    .animation(.default, value: viewModel.smartLists)
  }

  private var emptyState: some View {
    VStack {
      Text("No Smart Lists. Tap + to create one.")
        .foregroundColor(.secondary)
        .padding()
      Spacer()
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      AppIcon.addSmartList.labelButton {
        sheet(id: "smart-list-create") {
          SmartListEditorView(viewModel: SmartListEditorViewModel(mode: .create))
        }
      }
    }
    ToolbarItem(placement: .primaryAction) {
      if viewModel.editMode == .active {
        AppIcon.editFinished.labelButton { viewModel.editMode = .inactive }
      } else {
        AppIcon.editItems.labelButton { viewModel.editMode = .active }
      }
    }
  }
}

#if DEBUG
#Preview {
  EpisodesView()
    .preview()
}
#endif
