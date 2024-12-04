// Copyright Justin Bishop, 2024

import SwiftUI

struct PodcastsView: View {
  @State private var podcastsViewModel = PodcastsViewModel()

  var body: some View {
    Button("Hello World") { Navigation.shared.currentTab = .settings }
  }
}

#Preview {
  Preview { PodcastsView() }
}
