// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct TrendingPodcastView: View {
  @Environment(Alert.self) var alert

  @State private var viewModel: TrendingPodcastViewModel

  init(viewModel: TrendingPodcastViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HTMLText(viewModel.unsavedPodcast.description)
        .lineLimit(3)
        .padding(.horizontal)

      if viewModel.subscribable {
        Button("Subscribe") {
          viewModel.subscribe()
        }
      }

      SearchBar(
        text: $viewModel.episodeList.entryFilter,
        placeholder: "Filter episodes",
        imageName: "line.horizontal.3.decrease.circle"
      )

      if viewModel.episodeList.allEntries.isEmpty {
        Text("Loading episodes")
      } else {
        List(viewModel.episodeList.filteredEntries, id: \.guid) { unsavedEpisode in
          NavigationLink(
            value: UnsavedPodcastEpisode(
              unsavedPodcast: viewModel.unsavedPodcast,
              unsavedEpisode: unsavedEpisode
            ),
            label: {
              TrendingEpisodeListView(unsavedEpisode: unsavedEpisode)
            }
          )
        }
      }
    }
    .navigationTitle(viewModel.unsavedPodcast.title)
    .navigationDestination(
      for: UnsavedPodcastEpisode.self,
      destination: { unsavedPodcastEpisode in
        TrendingEpisodeView(
          viewModel: TrendingEpisodeViewModel(
            unsavedPodcastEpisode: unsavedPodcastEpisode
          )
        )
      }
    )
    .toolbar {
      if viewModel.isSelecting {
        ToolbarItem(placement: .topBarTrailing) {
          SelectableListMenu(list: viewModel.episodeList)
        }
      }

      if viewModel.isSelecting, viewModel.episodeList.anySelected {
        ToolbarItem(placement: .topBarTrailing) {
          Menu(
            content: {
              Button("Add To Top Of Queue") {
                viewModel.addSelectedEpisodesToTopOfQueue()
              }
              Button("Add To Bottom Of Queue") {
                viewModel.addSelectedEpisodesToBottomOfQueue()
              }
              Button("Replace Queue") {
                viewModel.replaceQueue()
              }
              Button("Replace Queue and Play") {
                viewModel.replaceQueueAndPlay()
              }
            },
            label: {
              Image(systemName: "text.badge.plus")
            }
          )
        }
      }

      if viewModel.isSelecting {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") {
            viewModel.isSelecting = false
          }
        }
      } else {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Select Episodes") {
            viewModel.isSelecting = true
          }
        }
      }
    }
    .toolbarRole(.editor)
    .task { await viewModel.execute() }
  }
}

#Preview {
  @Previewable @State var viewModel: TrendingPodcastViewModel?
  @ObservationIgnored @LazyInjected(\.repo) var repo

  NavigationStack {
    if let viewModel = viewModel {
      TrendingPodcastView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let unsavedPodcast = try! await PreviewHelpers.loadUnsavedPodcast()
    if let existingPodcastSeries = try? await repo.podcastSeries(unsavedPodcast.feedURL) {
      try! await repo.delete(existingPodcastSeries.id)
    }
    viewModel = TrendingPodcastViewModel(
      category: "News",
      unsavedPodcast: try! await PreviewHelpers.loadUnsavedPodcast()
    )
  }
}
