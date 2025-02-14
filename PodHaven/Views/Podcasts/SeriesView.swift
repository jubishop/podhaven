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
        Button(
          action: viewModel.subscribe,
          label: {
            Text("Subscribe")
          }
        )
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
        ToolbarItem(placement: .topBarLeading) {
          Button(
            action: {
              viewModel.isSelecting = false
            },
            label: {
              Text("Done")
            }
          )
        }
      }

      if viewModel.isSelecting {
        if viewModel.anySelected {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button(
                action: {
                  viewModel.addSelectedEpisodesToTopOfQueue()
                },
                label: {
                  Text("Add To Top Of Queue")
                }
              )

              Button(
                action: {
                  viewModel.addSelectedEpisodesToBottomOfQueue()
                },
                label: {
                  Text("Add To Bottom Of Queue")
                }
              )

              Button(
                action: {
                  viewModel.replaceQueue()
                },
                label: {
                  Text("Replace Queue")
                }
              )

              Button(
                action: {
                  viewModel.replaceQueueAndPlay()
                },
                label: {
                  Text("Replace Queue and Play")
                }
              )
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }
        }
      } else {
        ToolbarItem(placement: .topBarTrailing) {
          Button(
            action: {
              viewModel.isSelecting = true
            },
            label: {
              Text("Select Episodes")
            }
          )
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
