// Copyright Justin Bishop, 2024

import SwiftUI

struct SeriesView: View {
  let podcast: Podcast

  var body: some View {
    Text(podcast.title)
  }
}

//#Preview {
//  SeriesView(podcast: .constant())
//}
