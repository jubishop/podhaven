// Copyright Justin Bishop, 2024

import SwiftUI

struct PodcastsView: View {
  @State private var navigation = Navigation.shared
  @State private var podcastsViewModel = PodcastsViewModel()

  var body: some View {
    Button("Hello World") { navigation.currentTab = .settings }
  }
}

#Preview {
  Preview { PodcastsView() }
}
