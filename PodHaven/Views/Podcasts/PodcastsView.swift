// Copyright Justin Bishop, 2024

import SwiftUI

struct PodcastsView: View {
  @State private var viewModel = PodcastsViewModel()

  init(repository: PodcastRepository = .shared) {
    _viewModel = State(initialValue: PodcastsViewModel(repository: repository))
  }

  var body: some View {
    Button("Hello World") { Navigation.shared.currentTab = .settings }
  }
}

#Preview {
  Preview { PodcastsView(repository: .empty()) }
}
