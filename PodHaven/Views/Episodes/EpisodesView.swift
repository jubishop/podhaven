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
          Text(smartList.title)
        }
      }
      .onMove(perform: viewModel.moveSmartList)
      .onDelete(perform: viewModel.requestDeleteSmartList)
    }
    .environment(\.editMode, $viewModel.editMode)
    .animation(.default, value: viewModel.smartLists)
    .confirmationDialog(
      "Delete “\(viewModel.pendingDelete?.title ?? "Smart List")”?",
      isPresented: Binding(
        get: { viewModel.pendingDelete != nil },
        set: { if !$0 { viewModel.pendingDelete = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) { viewModel.confirmDeleteSmartList() }
    }
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
