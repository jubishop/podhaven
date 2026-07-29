// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import SwiftUI

struct TranscriptionQueueView: View {
  @State private var viewModel = TranscriptionQueueViewModel()

  var body: some View {
    content
      .navigationTitle("Transcription Queue")
      .toolbar { toolbar }
      .environment(\.editMode, $viewModel.editMode)
      .toolbarRole(.editor)
      .animation(.default, value: viewModel.entries)
      .task(viewModel.execute)
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.loadingState {
    case .loading:
      VStack {
        ProgressView("Loading Transcription Queue…")
          .foregroundStyle(.secondary)
          .padding()
        Spacer()
      }
    case .loaded:
      if viewModel.entries.isEmpty {
        ContentUnavailableView {
          AppIcon.transcribeEpisode.label("No Transcriptions")
        } description: {
          Text("Episodes you choose to transcribe will appear here.")
        }
      } else {
        queueList
      }
    case .failed:
      ContentUnavailableView {
        AppIcon.error.label("Couldn't Load Queue")
      } description: {
        Text("PodHaven couldn't load the episodes waiting for transcription.")
      } actions: {
        Button("Try Again") {
          viewModel.retry()
        }
      }
    }
  }

  private var queueList: some View {
    List(selection: $viewModel.selectedEpisodeIDs) {
      ForEach(viewModel.waitingEntries) { entry in
        queueRow(entry)
          .tag(entry.id)
          .swipeActions(edge: .leading, allowsFullSwipe: false) {
            queueActions(for: entry.id)
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            transcribeNowAction(for: entry.id)
          }
          .accessibilityActions {
            transcribeNowAction(for: entry.id)
            queueActions(for: entry.id)
          }
      }
      .onMove(perform: viewModel.move)
      .onDelete(perform: viewModel.remove)
    }
    .safeAreaInset(edge: .top, spacing: 12) {
      if let activeEntry = viewModel.activeEntry {
        NavigationLink(
          value: Navigation.Destination.episode(DisplayedEpisode(activeEntry.episode))
        ) {
          TranscriptionQueueRow(entry: activeEntry)
            .padding()
            .glassEffect(in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func queueActions(for episodeID: Episode.ID) -> some View {
    removeAction(for: episodeID)

    if viewModel.canMoveToTop(episodeID) {
      AppIcon.moveToTop
        .labelButton {
          viewModel.moveToTop(episodeID)
        }
        .labelStyle(.iconOnly)
    }
    if viewModel.canMoveToBottom(episodeID) {
      AppIcon.moveToBottom
        .labelButton {
          viewModel.moveToBottom(episodeID)
        }
        .labelStyle(.iconOnly)
    }
  }

  @ViewBuilder
  private func transcribeNowAction(for episodeID: Episode.ID) -> some View {
    if viewModel.canTranscribeNow(episodeID) {
      AppIcon.transcribeNow
        .labelButton {
          viewModel.transcribeNow(episodeID)
        }
        .labelStyle(.iconOnly)
    }
  }

  private func removeAction(for episodeID: Episode.ID) -> some View {
    AppIcon.removeFromQueue
      .labelButton {
        viewModel.remove(episodeID)
      }
      .labelStyle(.iconOnly)
  }

  @ViewBuilder
  private func queueRow(_ entry: TranscriptionQueueViewModel.Entry) -> some View {
    if viewModel.editMode.isEditing {
      TranscriptionQueueRow(entry: entry)
    } else {
      NavigationLink(value: Navigation.Destination.episode(DisplayedEpisode(entry.episode))) {
        TranscriptionQueueRow(entry: entry)
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if viewModel.loadingState == .loaded, !viewModel.waitingEntries.isEmpty {
      if viewModel.editMode.isEditing {
        ToolbarItem(placement: .topBarLeading) {
          if viewModel.allSelected {
            AppIcon.unselectAll.labelButton {
              viewModel.deselectAll()
            }
          } else {
            AppIcon.selectAll.labelButton {
              viewModel.selectAll()
            }
          }
        }
      }

      ToolbarItem(placement: .primaryAction) {
        EditButton()
      }

      if viewModel.editMode.isEditing {
        ToolbarItemGroup(placement: .bottomBar) {
          AppIcon.moveToTop
            .imageButton {
              viewModel.moveSelectedToTop()
            }
            .disabled(!viewModel.canMoveSelectedToTop)

          Spacer()

          Text("\(viewModel.selectedEpisodeIDs.count) Selected")
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(viewModel.selectedEpisodeIDs.count) episodes selected")

          Spacer()

          AppIcon.moveToBottom
            .imageButton {
              viewModel.moveSelectedToBottom()
            }
            .disabled(!viewModel.canMoveSelectedToBottom)

          AppIcon.removeFromQueue
            .imageButton {
              viewModel.removeSelected()
            }
            .disabled(viewModel.selectedEpisodeIDs.isEmpty)
        }
      }
    }
  }
}

private struct TranscriptionQueueRow: View {
  let entry: TranscriptionQueueViewModel.Entry

  @ScaledMetric(relativeTo: .body) private var imageSize: CGFloat = 56

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      SquareImage(image: entry.episode.image, size: imageSize)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text(entry.episode.title)
          .font(.body)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        Text(entry.episode.podcastTitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        ProgressView(value: entry.progress, total: 1)
          .tint(entry.isActive ? Color.accentColor : Color.secondary)

        Text(entry.statusText)
          .font(.caption)
          .foregroundStyle(entry.isActive ? Color.accentColor : Color.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(entry.episode.title), \(entry.episode.podcastTitle)")
    .accessibilityValue(entry.accessibilityValue)
  }
}

#if DEBUG
#Preview("Transcription Queue") {
  NavigationStack {
    TranscriptionQueueView()
  }
  .preview()
  .task {
    do {
      let repo = Container.shared.repo()
      let queue = Container.shared.transcriptionQueue()
      let thumbnails = Array(PreviewBundle.loadAllThumbnails().values)
      let duration: TimeInterval = 3600
      let unsavedEpisodes = try (0..<6)
        .map { index in
          try Create.unsavedEpisode(
            title: "Episode \(index + 1): \(String.random())",
            pubDate: index.daysAgo,
            duration: .seconds(duration),
            image: thumbnails[safe: index]?.url
          )
        }
      let series = try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(title: "The Preview Podcast"),
          unsavedEpisodes: unsavedEpisodes
        )
      )

      for (index, episode) in series.episodes.enumerated() {
        if index < 4 {
          let checkpoint = TranscriptionCheckpoint(
            segments: [],
            audioTime: Double(index + 1) * 420,
            duration: duration,
            locale: TranscriptionAvailability.locale.identifier(.bcp47),
            audioSHA256: String(repeating: "\(index)", count: 64)
          )
          try await repo.saveTranscriptionCheckpoint(checkpoint, for: episode.id)
        }
        try await queue.enqueue(episode.id)
      }

      if let activeEpisode = series.episodes.first {
        queue.setProgress(0.38, for: activeEpisode.id)
      }
    } catch {
      print("Preview error: \(error)")
    }
  }
}
#endif
