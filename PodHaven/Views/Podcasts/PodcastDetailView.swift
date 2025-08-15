// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import NukeUI
import SwiftUI

struct PodcastDetailView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: PodcastDetailViewModel

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  init(viewModel: PodcastDetailViewModel) {
    Self.log.debug(
      """
      Showing PodcastDetailView
        viewModel: \(viewModel.podcast.toString)
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

        List(viewModel.episodeList.filteredEntries) { episode in
          NavigationLink(
            value: Navigation.Podcasts.Destination.episode(
              PodcastEpisode(podcast: viewModel.podcast, episode: episode)
            ),
            label: {
              EpisodeListView(
                viewModel: EpisodeListViewModel(
                  isSelected: $viewModel.episodeList.isSelected[episode],
                  item: episode,
                  isSelecting: viewModel.episodeList.isSelecting
                )
              )
            }
          )
          .episodeQueueableSwipeActions(viewModel: viewModel, episode: episode)
          .episodeQueueableContextMenu(viewModel: viewModel, episode: episode)
        }
        .animation(.default, value: viewModel.episodeList.filteredEntries)
        .refreshable {
          do {
            try await viewModel.refreshSeries()
          } catch {
            Self.log.error(error)
            if ErrorKit.baseError(for: error) is CancellationError { return }
            alert(ErrorKit.message(for: error))
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
      LazyImage(url: viewModel.podcast.image) { state in
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
        Text(viewModel.podcast.title)
          .font(.title3)
          .fontWeight(.bold)
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        if let link = viewModel.podcast.link {
          Link(destination: link) {
            HStack(spacing: 4) {
              Image(systemName: "link")
              Text("Visit Website")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
          }
        }

        Button(action: {
          if viewModel.podcast.subscribed {
            viewModel.unsubscribe()
          } else {
            viewModel.subscribe()
          }
        }) {
          HStack(spacing: 4) {
            Image(systemName: viewModel.podcast.subscribed ? "minus.circle" : "plus.circle")
            Text(viewModel.podcast.subscribed ? "Unsubscribe" : "Subscribe")
          }
          .font(.caption)
          .foregroundColor(.accentColor)
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
      HTMLText(viewModel.podcast.description)
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
            ForEach(PodcastDetailViewModel.FilterMethod.allCases, id: \.self) { filterMethod in
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
#Preview("Changelog") {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    await PreviewHelpers.dataFetcher
      .respond(
        to: URL(string: "https://changelog.com/podcast/feed")!,
        data: PreviewBundle.loadAsset(named: "changelog", in: .FeedRSS)
      )
    podcast = try? await PreviewHelpers.loadSeries(fileName: "changelog").podcast
  }
}

#Preview("Pod Save America") {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    await PreviewHelpers.dataFetcher
      .respond(
        to: URL(string: "https://feeds.simplecast.com/dxZsm5kX")!,
        data: PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
      )
    podcast = try? await PreviewHelpers.loadSeries(fileName: "pod_save_america").podcast
  }
}
#endif
