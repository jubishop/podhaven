// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct CategoryGrid: View {
  @DynamicInjected(\.alert) private var alert

  private let viewModel: SearchViewModel

  init(viewModel: SearchViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      TokenGridView(
        tokens: viewModel.categories,
        width: viewModel.width,
        horizontalSpacing: 8,
        verticalSpacing: 8
      ) { category in
        Button(category) {
          viewModel.categorySelected(category)
        }
        .font(.caption)
        .padding(4)
        .background(Color.blue.opacity(0.2))
        .foregroundColor(.blue)
        .cornerRadius(4)
      }
      .background(Color(.systemBackground))
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var viewModel = SearchViewModel()

  NavigationStack {
    if viewModel.width > 0 {
      CategoryGrid(viewModel: viewModel)
    }
  }
  .backgroundSizeReader { size in
    viewModel.width = size.width
  }
  .padding()
  .preview()
}
#endif
