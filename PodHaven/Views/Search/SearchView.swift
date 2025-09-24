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
              AppIcon.trending.coloredImage
              VStack(alignment: .leading) {
                Text(AppIcon.trending.text)
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
              AppIcon.searchPodcasts.coloredImage
              VStack(alignment: .leading) {
                Text(AppIcon.searchPodcasts.text)
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
              AppIcon.searchEpisodes.coloredImage
              VStack(alignment: .leading) {
                Text(AppIcon.searchEpisodes.text)
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
              AppIcon.manualEntry.coloredImage
              VStack(alignment: .leading) {
                Text(AppIcon.manualEntry.text)
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
