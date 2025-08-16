// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SearchView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    NavigationStack(path: $navigation.search.path) {
      Form {
        NavigationLink(
          value: Navigation.Search.Destination.searchType(.trending),
          label: { Text("Trending") }
        )
      }
      .navigationTitle("Search")
      .navigationDestination(
        for: Navigation.Search.Destination.self,
        destination: navigation.search.navigationDestination
      )
    }
  }
}
