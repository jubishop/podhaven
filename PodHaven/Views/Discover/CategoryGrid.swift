// Copyright Justin Bishop, 2025

import SwiftUI

struct CategoryGrid: View {
  @Environment(Alert.self) var alert

  private let viewModel: DiscoverViewModel

  init(viewModel: DiscoverViewModel) {
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
        Button(
          action: {
            Task {
              do {
                try await viewModel.categorySelected(category)
              } catch {
                alert.andReport(error)
              }
            }
          },
          label: {
            Text(category)
              .font(.caption)
              .padding(4)
              .background(Color.blue.opacity(0.2))
              .foregroundColor(.blue)
              .cornerRadius(4)
          }
        )
      }
      .background(Color(.systemBackground))
    }
  }
}

#Preview {
  @Previewable @State var viewModel = DiscoverViewModel()

  NavigationStack {
    if viewModel.width > 0 {
      CategoryGrid(viewModel: viewModel)
    }
  }
  .background(
    SizeReader { size in
      viewModel.width = size.width
    }
  )
  .padding()
  .preview()
}
