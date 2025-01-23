// Copyright Justin Bishop, 2025

import SwiftUI

struct CategoryGrid: View {
  @Environment(Alert.self) var alert

  @State private var paddedWidth: CGFloat

  private let viewModel: DiscoverViewModel

  init(viewModel: DiscoverViewModel) {
    self.viewModel = viewModel
    self.paddedWidth = viewModel.width
  }

  var body: some View {
    ScrollView {
      TokenGridView(
        tokens: DiscoverViewModel.categories,
        width: paddedWidth,
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
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.width
      } action: { newWidth in
        paddedWidth = newWidth
      }
    }
  }
}

#Preview {
  @Previewable @State var viewModel = DiscoverViewModel()

  NavigationStack {
    if viewModel.width > 0 {
      CategoryGrid(viewModel: viewModel)
        .padding()
        .frame(width: viewModel.width)
    }
  }
  .preview()
  .onGeometryChange(for: CGFloat.self) { geometry in
    geometry.size.width
  } action: { newWidth in
    viewModel.width = newWidth
  }
}
