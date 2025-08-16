// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchPodcastsView: View {
  var body: some View {
    VStack {
      Text("Search Podcasts")
        .font(.title)
      Text("Coming Soon")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .navigationTitle("Search Podcasts")
    .navigationBarTitleDisplayMode(.large)
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    SearchPodcastsView()
  }
  .preview()
}
#endif
