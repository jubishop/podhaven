// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SearchView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.sheet) private var sheet
  @InjectedObservable(\.searchViewModel) private var viewModel

  @State private var gridItemSize: CGFloat = 100

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.search) {
      Group {
        if viewModel.isShowingSearchResults {
          searchResultsView
        } else {
          trendingView
        }
      }
      .navigationTitle(navigationTitle)
      .toolbar {
        manualEntryToolbarItem
        trendingMenuToolbarItem
      }
    }
    .task(viewModel.execute)
    .onDisappear { viewModel.disappear() }
  }

  // MARK: - Content Builders

  @ViewBuilder
  private var searchResultsView: some View {
    let state = viewModel.searchState

    ScrollView {
      switch state {
      case .idle:
        placeholderView(
          icon: AppIcon.search,
          title: "Search for podcasts",
          message: "Enter a podcast name or keyword to get started."
        )

      case .loading, .loaded:
        if !viewModel.searchResults.isEmpty {
          resultsGrid(unsavedPodcasts: viewModel.searchResults)
            .overlay(alignment: .top) {
              if state == .loading {
                loadingView(text: "Searching…")
              }
            }
        } else if state == .loading {
          loadingView(text: "Searching…")
        } else {
          placeholderView(
            icon: AppIcon.search,
            title: "No results found",
            message: "Try different search terms or check your spelling."
          )
        }

      case .error(let message):
        errorView(title: "Search Error", message: message)
      }
    }
    .refreshable {
      await viewModel.refreshSearch()
    }
  }

  @ViewBuilder
  private var trendingView: some View {
    let section = viewModel.currentTrendingSection
    let state = section.state

    ScrollView {
      switch state {
      case .loaded, .loading, .idle:
        if !section.podcasts.isEmpty {
          resultsGrid(unsavedPodcasts: section.podcasts)
            .overlay(alignment: .top) {
              if state == .loading {
                loadingView(text: "Fetching top \(section.title) podcasts…")
              }
            }
        } else {
          loadingView(text: "Fetching top \(section.title) podcasts…")
        }

      case .error(let message):
        errorView(title: "Unable to Load", message: message)
      }
    }
    .refreshable {
      await viewModel.refreshCurrentTrendingSection()
    }
  }

  // MARK: - Section Grids

  @ViewBuilder
  private func resultsGrid(unsavedPodcasts: [UnsavedPodcast]) -> some View {
    ItemGrid(items: unsavedPodcasts, minimumGridSize: gridItemSize) { podcast in
      NavigationLink(
        value: Navigation.Destination.podcast(DisplayedPodcast(podcast)),
        label: {
          VStack {
            SquareImage(image: podcast.image, size: $gridItemSize)
            Text(podcast.title)
              .font(.caption)
              .lineLimit(1)
          }
        }
      )
      .buttonStyle(.plain)
    }
    .padding(.horizontal)
    .padding(.top)
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var manualEntryToolbarItem: some ToolbarContent {
    ToolbarItem(placement: .secondaryAction) {
      Button(
        action: {
          sheet {
            ManualFeedEntryView(viewModel: ManualFeedEntryViewModel())
          }
        },
        label: {
          Label("Add Feed", systemImage: AppIcon.manualEntry.systemImageName)
        }
      )
      .accessibilityLabel("Add Feed URL manually")
    }
  }

  @ToolbarContentBuilder
  private var trendingMenuToolbarItem: some ToolbarContent {
    if !viewModel.isShowingSearchResults {
      ToolbarItem(placement: .primaryAction) {
        Menu(
          content: {
            ForEach(viewModel.trendingSections, id: \.title) { trendingSection in
              trendingSection.icon
                .labelButton {
                  viewModel.selectTrendingSection(trendingSection)
                }
                .accessibilityLabel(Text("Select trending section: \(trendingSection.title)"))
            }
          },
          label: {
            viewModel.currentTrendingSection.icon.coloredLabel
              .font(.title2.weight(.semibold))
          }
        )
      }
    }
  }

  // MARK: - Reusable Views / Data

  private func loadingView(text: String) -> some View {
    ProgressView(text)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .allowsHitTesting(false)
  }

  private func placeholderView(icon: AppIcon, title: String, message: String) -> some View {
    VStack(spacing: 16) {
      icon.coloredImage
        .font(.system(size: 48))
      Text(title)
        .font(.headline)
      Text(message)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func errorView(title: String, message: String) -> some View {
    placeholderView(icon: AppIcon.error, title: title, message: message)
  }

  fileprivate var navigationTitle: String {
    if viewModel.isShowingSearchResults {
      return viewModel.trimmedSearchText
    }

    return viewModel.currentTrendingSection.title
  }
}
