// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct SearchedPodcastGridItem: View {
  @State private var width: CGFloat = 0
  @State private var viewModel: SearchedPodcastGridItemViewModel

  private let cornerRadius: CGFloat = 8

  init(viewModel: SearchedPodcastGridItemViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    NavigationLink(value: Navigation.Search.Destination.unsavedPodcast(viewModel.unsavedPodcast))
    {
      VStack {
        LazyImage(url: viewModel.searchedPodcast.unsavedPodcast.image) { state in
          if let image = state.image {
            image
              .resizable()
              .cornerRadius(cornerRadius)
          } else {
            ZStack {
              Color.gray
                .cornerRadius(cornerRadius)
              VStack {
                Image(systemName: "photo")
                  .resizable()
                  .scaledToFit()
                  .frame(width: width / 2, height: width / 2)
                  .foregroundColor(.white.opacity(0.8))
                Text("No Image")
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.8))
              }
            }
          }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
          geometry.size.width
        } action: { newWidth in
          width = newWidth
        }
        .frame(height: width)

        Text(viewModel.searchedPodcast.unsavedPodcast.title)
          .font(.caption)
          .lineLimit(1)
          .foregroundColor(.primary)
      }
    }
    .contextMenu {
      Button("Subscribe") {
        viewModel.subscribe()
      }
    }
  }
}

#if DEBUG
//#Preview {
//  LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
//    SearchedPodcastGridItem(
//      viewModel: SearchedPodcastGridItemViewModel(
//        searchedPodcast: SearchedPodcast(
//          searchedText: "Technology",
//          unsavedPodcast: try! UnsavedPodcast(
//            feedURL: try! FeedURL(URL(string: "https://example.com/feed")!),
//            title: "Sample Podcast",
//            image: URL(string: "https://example.com/image.jpg")!,
//            description: "A sample podcast for preview"
//          )
//        )
//      )
//    )
//  }
//  .preview()
//}
#endif
