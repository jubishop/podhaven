// Copyright Justin Bishop, 2025

import SwiftUI

/// A reusable menu component for sorting functionality
struct SortMenu<ViewModel: Sortable>: View {
  let viewModel: ViewModel

  var body: some View {
    Menu("Sort") {
      ForEach(ViewModel.SortMethod.allCases, id: \.rawValue) { method in
        Button(method.rawValue) {
          viewModel.sort(by: method)
        }
        .disabled(viewModel.currentSortMethod?.rawValue == method.rawValue)
      }
    }
  }
}
