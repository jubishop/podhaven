// Copyright Justin Bishop, 2025

import GRDB
import SwiftUI

struct SeriesView: View {
  @Environment(Alert.self) var alert

  @State private var viewModel: SeriesViewModel

  init(viewModel: SeriesViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HTMLText(viewModel.podcast.description)
        .lineLimit(3)
        .padding(.horizontal)

      Text("Last updated: \(viewModel.podcast.formattedLastUpdate)")
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal)

      if !viewModel.podcast.subscribed {
        Button("Subscribe") {
          viewModel.subscribe()
        }
      }

      SearchBar(
        text: $viewModel.episodeFilter,
        placeholder: "Filter episodes",
        imageName: "line.horizontal.3.decrease.circle"
      )

      List(viewModel.filteredEpisodes) { episode in
        NavigationLink(
          value: episode,
          label: {
            EpisodeListView(
              viewModel: EpisodeListViewModel(
                isSelected: $viewModel.isSelected[episode],
                episode: episode,
                isSelecting: viewModel.isSelecting
              )
            )
          }
        )
      }
      .refreshable {
        do {
          try await viewModel.refreshSeries()
        } catch {
          alert.andReport("Failed to refresh series: \(viewModel.podcast.toString)")
        }
      }
    }
    .navigationTitle(viewModel.podcast.title)
    .navigationDestination(for: Episode.self) { episode in
      EpisodeView(
        viewModel: EpisodeViewModel(
          podcastEpisode: PodcastEpisode(
            podcast: viewModel.podcast,
            episode: episode
          )
        )
      )
    }
    .toolbar {
      if viewModel.isSelecting {
        ToolbarItem(placement: .topBarTrailing) {
          Menu(
            content: {
              if viewModel.anyNotSelected {
                Button("Select All") {
                  viewModel.selectAllEpisodes()
                }
              }
              if viewModel.anySelected {
                Button("Unselect All") {
                  viewModel.unselectAllEpisodes()
                }
              }
            },
            label: {
              Image(systemName: "checklist")
            }
          )
        }
      }

      if viewModel.isSelecting, viewModel.anySelected {
        ToolbarItem(placement: .topBarTrailing) {
          Menu(
            content: {
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
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast = podcast {
      SeriesView(viewModel: SeriesViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    podcast = try? await PreviewHelpers.loadSeries().podcast
  }
}
