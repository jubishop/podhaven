// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SearchView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.search) {
      Form {
        NavigationLink(
          value: Navigation.Destination.searchType(.trending),
          label: {
            HStack {
              AppLabel.trending.image
                .foregroundColor(.orange)
              VStack(alignment: .leading) {
                Text(AppLabel.trending.text)
                  .font(.headline)
                Text("Browse trending podcasts")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        )

        NavigationLink(
          value: Navigation.Destination.searchType(.podcasts),
          label: {
            HStack {
              AppLabel.searchPodcasts.image
                .foregroundColor(.blue)
              VStack(alignment: .leading) {
                Text(AppLabel.searchPodcasts.text)
                  .font(.headline)
                Text("Find podcasts by title or keywords")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        )

        NavigationLink(
          value: Navigation.Destination.searchType(.episodes),
          label: {
            HStack {
              AppLabel.searchEpisodes.image
                .foregroundColor(.green)
              VStack(alignment: .leading) {
                Text(AppLabel.searchEpisodes.text)
                  .font(.headline)
                Text("Find episodes with a specific person")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        )

        NavigationLink(
          value: Navigation.Destination.searchType(.manualEntry),
          label: {
            HStack {
              AppLabel.manualEntry.image
                .foregroundColor(.purple)
              VStack(alignment: .leading) {
                Text(AppLabel.manualEntry.text)
                  .font(.headline)
                Text("Paste a podcast RSS feed URL directly")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        )
      }
      .navigationTitle("Search")
    }
  }
}
