// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingView: View {
  var body: some View {
    Form {
      NavigationLink(
        value: Navigation.Destination.category(SearchService.allCategories),
        label: { Text(SearchService.allCategories) }
      )

      ForEach(SearchService.categories, id: \.self) { category in
        NavigationLink(
          value: Navigation.Destination.category(category),
          label: { Text(category) }
        )
      }
    }
    .navigationTitle("Categories")
  }
}
