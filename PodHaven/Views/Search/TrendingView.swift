// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingView: View {
  var body: some View {
    Form {
      ForEach(SearchService.categories, id: \.self) { category in
        NavigationLink(category) {
          TrendingCategoryView(category: category)
        }
      }
    }
    .navigationTitle("Trending Categories")
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    TrendingView()
  }
  .preview()
}
#endif
