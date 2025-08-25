// Copyright Justin Bishop, 2025

import SwiftUI

struct UpNextToolbarModifier: ViewModifier {
  @State private var viewModel: UpNextViewModel

  init(viewModel: UpNextViewModel) {
    self.viewModel = viewModel
  }

  func body(content: Content) -> some View {
    content
      .toolbar {
        if viewModel.isEditing {
          ToolbarItem(placement: .topBarTrailing) {
            SelectableListMenu(list: viewModel.episodeList)
          }

          if viewModel.episodeList.anySelected {
            ToolbarItem(placement: .topBarTrailing) {
              Menu(
                content: {
                  Button("Delete Selected") {
                    viewModel.deleteSelected()
                  }
                },
                label: {
                  AppLabel.unsubscribe.image
                }
              )
            }
          }
        } else {
          ToolbarItem(placement: .topBarLeading) {
            Text(viewModel.totalQueueDuration.shortDescription)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          ToolbarItem(placement: .topBarTrailing) {
            Menu("Sort") {
              ForEach(UpNextViewModel.SortMethod.allCases, id: \.self) { method in
                Button(method.rawValue) {
                  viewModel.sort(by: method)
                }
              }
            }
          }
        }

        ToolbarItem(placement: (viewModel.isEditing ? .topBarLeading : .topBarTrailing)) {
          EditButton()
            .environment(\.editMode, $viewModel.editMode)
        }
      }
      .toolbarRole(.editor)
  }
}

extension View {
  func upNextToolbar(
    viewModel: UpNextViewModel
  ) -> some View {
    self.modifier(UpNextToolbarModifier(viewModel: viewModel))
  }
}
