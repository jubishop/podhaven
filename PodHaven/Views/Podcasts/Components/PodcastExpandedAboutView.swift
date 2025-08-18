// Copyright Justin Bishop, 2025

import SwiftUI

struct PodcastExpandedAboutView: View {
  let podcast: any PodcastDisplayable

  var body: some View {
    ScrollView {
      HTMLText(podcast.description)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}
