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
    Group {
      if viewModel.displayAboutSection {
        ScrollView {
          VStack(spacing: 8) {
            podcastHeaderSection
            podcastMetadataSection
            podcastAboutSectionExpanded
            podcastActionsSection
          }
          .padding()
        }
      } else {
        VStack(spacing: 0) {
          VStack(spacing: 8) {
            podcastHeaderSection
            podcastMetadataSection
            podcastAboutSectionCollapsed
            podcastActionsSection
          }
          .padding(.horizontal)

          episodeFilterSection

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
    }
    .queueableSelectableEpisodesToolbar(viewModel: viewModel, episodeList: $viewModel.episodeList)
    .task(viewModel.execute)
  }

  // MARK: - Header Components

  private var podcastHeaderSection: some View {
    HStack(alignment: .top, spacing: 16) {
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
          .font(.title2)
          .fontWeight(.bold)
          .lineLimit(3)
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
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var podcastMetadataSection: some View {
    HStack {
      metadataItem(
        icon: "calendar",
        label: "Updated",
        value: viewModel.podcast.lastUpdate.usShortWithTime
      )

      Spacer()

      metadataItem(
        icon: "list.bullet",
        label: "Episodes",
        value: "\(viewModel.episodeList.allEntries.count)"
      )
    }
    .padding(.horizontal, 8)
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

  private var podcastAboutSectionCollapsed: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("About")
          .font(.headline)
          .fontWeight(.semibold)
        Spacer()
        if !viewModel.podcast.description.isEmpty {
          Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
              viewModel.displayAboutSection = true
            }
          }) {
            HStack(spacing: 4) {
              Text("Show About")
              Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
          }
        }
      }
    }
  }

  private var podcastAboutSectionExpanded: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("About")
          .font(.headline)
          .fontWeight(.semibold)
        Spacer()
        Button(action: {
          withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.displayAboutSection = false
          }
        }) {
          HStack(spacing: 4) {
            Text("Hide About")
            Image(systemName: "chevron.down")
          }
          .font(.caption)
          .foregroundColor(.accentColor)
        }
      }

      HTMLText(viewModel.podcast.description)
        .multilineTextAlignment(.leading)
    }
  }

  private var podcastActionsSection: some View {
    VStack(spacing: 12) {
      if !viewModel.podcast.subscribed {
        Button(action: viewModel.subscribe) {
          HStack {
            Image(systemName: "plus.circle.fill")
            Text("Subscribe")
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.accentColor)
          .foregroundColor(.white)
          .cornerRadius(10)
        }
      }
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
      .padding(.horizontal)

      Divider()
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var podcast: Podcast?

  NavigationStack {
    if let podcast {
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
    }
  }
  .preview()
  .task {
    podcast = try? await PreviewHelpers.loadSeries().podcast
  }
}
#endif
