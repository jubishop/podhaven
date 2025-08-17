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
          label: {
            HStack {
              Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(.orange)
              VStack(alignment: .leading) {
                Text("Trending")
                  .font(.headline)
                Text("Browse trending podcasts")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        )

        NavigationLink(
          value: Navigation.Search.Destination.searchType(.searchTerm),
          label: {
            HStack {
              Image(systemName: "magnifyingglass")
                .foregroundColor(.blue)
              VStack(alignment: .leading) {
                Text("Search by Term")
                  .font(.headline)
                Text("Find podcasts by keywords")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        )

        NavigationLink(
          value: Navigation.Search.Destination.searchType(.searchTitle),
          label: {
            HStack {
              Image(systemName: "textformat.abc")
                .foregroundColor(.green)
              VStack(alignment: .leading) {
                Text("Search by Title")
                  .font(.headline)
                Text("Find podcasts by exact title")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
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
