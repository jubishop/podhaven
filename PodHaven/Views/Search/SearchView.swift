// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SearchView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    NavigationStack(path: $navigation.search.path) {
      Form {
        NavigationLink("Trending") {
          TrendingView()
        }
      }
      .navigationTitle("Search")
      .navigationDestination(
        for: Navigation.Search.Destination.self,
        destination: navigation.search.navigationDestination
      )
    }
  }
}

#if DEBUG
#Preview {
  SearchView()
    .preview()
}
#endif
