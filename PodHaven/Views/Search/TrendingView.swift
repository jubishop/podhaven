// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingView: View {
  var body: some View {
    Form {
      ForEach(SearchService.categories, id: \.self) { category in
        NavigationLink(
          value: Navigation.Search.Destination.category(category),
          label: { Text(category) }
        )
      }
    }
    .navigationTitle("Trending Categories")
  }
}
