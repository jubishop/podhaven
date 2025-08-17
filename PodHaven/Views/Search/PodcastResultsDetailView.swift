// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import NukeUI
import SwiftUI

struct PodcastResultsDetailView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: PodcastResultsDetailViewModel

  private static let log = Log.as(LogSubsystem.SearchView.podcastDetail)

  init(viewModel: PodcastResultsDetailViewModel) {
    Self.log.debug(
      """
      Showing PodcastResultsDetailView
        viewModel: \(viewModel.unsavedPodcast.title)
      """
    )
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 4) {
        Group {
          podcastHeaderSection
          podcastAboutHeader
          if viewModel.displayAboutSection {
            Divider()
            podcastMetadataSection
            Divider()
            podcastExpandedAboutSection
          }
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
      }
      if !viewModel.displayAboutSection {
        episodeFilterSection.padding(.horizontal)

        if viewModel.subscribable {
          if viewModel.episodeList.filteredEntries.isEmpty {
            VStack {
              Text("No matching episodes found.")
                .foregroundColor(.secondary)
                .padding()
              Spacer()
            }
          } else {
            List(viewModel.episodeList.filteredEntries, id: \.guid) { unsavedEpisode in
              NavigationLink(
                value: Navigation.Search.Destination.searchedPodcastEpisode(
                  SearchedPodcastEpisode(
                    searchedText: viewModel.searchedText,
                    unsavedPodcastEpisode: UnsavedPodcastEpisode(
                      unsavedPodcast: viewModel.unsavedPodcast,
                      unsavedEpisode: unsavedEpisode
                    )
                  )
                ),
                label: {
                  EpisodeResultsListView(
                    viewModel: EpisodeResultsListViewModel(
                      isSelected: $viewModel.episodeList.isSelected[unsavedEpisode],
                      item: unsavedEpisode,
                      isSelecting: viewModel.episodeList.isSelecting
                    )
                  )
                }
              )
              .episodeQueueableSwipeActions(viewModel: viewModel, episode: unsavedEpisode)
              .episodeQueueableContextMenu(viewModel: viewModel, episode: unsavedEpisode)
            }
            .animation(.default, value: viewModel.episodeList.filteredEntries)
          }
        } else {
          VStack {
            Text("Loading episodes...")
              .foregroundColor(.secondary)
              .padding()
            Spacer()
          }
        }
      }
    }
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task(viewModel.execute)
  }

  // MARK: - Header Components

  private var podcastHeaderSection: some View {
    HStack(alignment: .top, spacing: 12) {
      LazyImage(url: viewModel.unsavedPodcast.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
              VStack {
                Image(systemName: "photo")
                  .foregroundColor(.white.opacity(0.8))
                  .font(.title)
                Text("No Image")
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.8))
              }
            )
        }
      }
      .frame(width: 120, height: 120)
      .clipped()
      .cornerRadius(12)
      .shadow(radius: 4)

      VStack(alignment: .leading, spacing: 8) {
        Text(viewModel.unsavedPodcast.title)
          .font(.title3)
          .fontWeight(.bold)
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        if let link = viewModel.unsavedPodcast.link {
          Link(destination: link) {
            HStack(spacing: 4) {
              Image(systemName: "link")
              Text("Visit Website")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
          }
        }

        if viewModel.subscribable {
          Button(action: {
            viewModel.subscribe()
          }) {
            HStack(spacing: 4) {
              Image(systemName: "plus.circle")
              Text("Subscribe")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var podcastMetadataSection: some View {
    HStack {
      metadataItem(
        icon: "calendar",
        label: "Updated",
        value: viewModel.mostRecentEpisodeDate.usShortWithTime
      )

      Spacer()

      metadataItem(
        icon: "list.bullet",
        label: "Episodes",
        value: "\(viewModel.episodeList.allEntries.count)"
      )
    }
  }

  private var podcastAboutHeader: some View {
    HStack {
      if viewModel.displayAboutSection {
        Text("About")
          .font(.headline)
          .fontWeight(.semibold)
      } else {
        HStack(spacing: 4) {
          Image(systemName: "calendar")
            .foregroundColor(.secondary)
            .font(.caption)
          Text(viewModel.mostRecentEpisodeDate.usShortWithTime)
            .font(.subheadline)
            .fontWeight(.medium)
        }
      }
      Spacer()
      Button(action: {
        withAnimation(.easeInOut(duration: 0.3)) {
          viewModel.displayAboutSection.toggle()
        }
      }) {
        HStack(spacing: 4) {
          Text(viewModel.displayAboutSection ? "Hide About" : "Show About")
          Image(systemName: viewModel.displayAboutSection ? "chevron.up" : "chevron.down")
        }
        .font(.caption)
        .foregroundColor(.accentColor)
      }
    }
  }

  private var podcastExpandedAboutSection: some View {
    ScrollView {
      HTMLText(viewModel.unsavedPodcast.description)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var episodeFilterSection: some View {
    VStack(spacing: 8) {
      Divider()

      HStack {
        SearchBar(
          text: $viewModel.episodeList.entryFilter,
          placeholder: "Filter episodes",
          imageName: "line.horizontal.3.decrease.circle"
        )

        Menu(
          content: {
            ForEach(PodcastResultsDetailViewModel.FilterMethod.allCases, id: \.self) { filterMethod in
              Button(filterMethod.rawValue) {
                viewModel.currentFilterMethod = filterMethod
              }
              .disabled(viewModel.currentFilterMethod == filterMethod)
            }
          },
          label: {
            Image(systemName: "line.horizontal.3.decrease.circle")
          }
        )
      }

      Divider()
    }
  }

  private func metadataItem(icon: String, label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .foregroundColor(.secondary)
          .font(.caption)
        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Text(value)
        .font(.subheadline)
        .fontWeight(.medium)
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var viewModel: PodcastResultsDetailViewModel?
  @ObservationIgnored @DynamicInjected(\.repo) var repo

  NavigationStack {
    if let viewModel {
      PodcastResultsDetailView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let unsavedPodcast = try! await PreviewHelpers.loadUnsavedPodcast()
    if let existingPodcastSeries = try? await repo.podcastSeries(unsavedPodcast.feedURL) {
      try! await repo.delete(existingPodcastSeries.id)
    }
    viewModel = PodcastResultsDetailViewModel(
      searchedPodcast: SearchedPodcast(searchedText: "News", unsavedPodcast: unsavedPodcast)
    )
  }
}
#endif
