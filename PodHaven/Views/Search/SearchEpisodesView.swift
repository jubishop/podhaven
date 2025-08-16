// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchEpisodesView: View {
  var body: some View {
    VStack {
      Text("Search Episodes by Person")
        .font(.title)
      Text("Coming Soon")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .navigationTitle("Search Episodes")
    .navigationBarTitleDisplayMode(.large)
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    SearchEpisodesView()
  }
  .preview()
}
#endif
