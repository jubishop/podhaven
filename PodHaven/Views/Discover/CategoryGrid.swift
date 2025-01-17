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
        tokens: viewModel.categories,
        width: paddedWidth,
        horizontalSpacing: viewModel.categories.count > 10 ? 8 : 16,
        verticalSpacing: viewModel.categories.count > 10 ? 8 : 16
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
              .font(viewModel.categories.count > 10 ? .caption : .title)
              .padding(viewModel.categories.count > 8 ? 4 : 10)
              .background(Color.blue.opacity(0.2))
              .foregroundColor(.blue)
              .cornerRadius(4)
          }
        )
      }
      .padding(.bottom)
      .background(Color(.systemBackground))
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.width
      } action: { newWidth in
        paddedWidth = newWidth
      }
      .padding(.horizontal)
    }
  }
}

#Preview {
  @Previewable @State var viewModel = DiscoverViewModel()

  NavigationStack {
    if viewModel.width > 0 {
      CategoryGrid(viewModel: viewModel).frame(width: viewModel.width)
    }
  }
  .preview()
  .onGeometryChange(for: CGFloat.self) { geometry in
    geometry.size.width
  } action: { newWidth in
    viewModel.width = newWidth
  }
}
