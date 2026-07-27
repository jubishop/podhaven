// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import SwiftUI

@Observable @MainActor final class TranscriptionQueueViewModel {
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor
  @ObservationIgnored @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private static let log = Log.as(LogSubsystem.SettingsView.transcriptionQueue)

  enum LoadingState: Equatable {
    case loading
    case loaded
    case failed
  }

  struct Entry: Equatable, Identifiable {
    let episode: PodcastEpisode
    let progress: Double
    let isActive: Bool

    var id: Episode.ID { episode.id }

    var percentage: Int {
      Int((progress * 100).rounded())
    }

    var statusText: String {
      if isActive {
        return "Transcribing · \(percentage)%"
      }
      return "Waiting · \(percentage)%"
    }

    var accessibilityValue: String {
      if isActive {
        return "Transcribing, \(percentage) percent"
      }
      return "Waiting, \(percentage) percent complete"
    }
  }

  private(set) var loadingState: LoadingState = .loading
  private(set) var episodes: [PodcastEpisode] = []
  private(set) var checkpointProgress: [Episode.ID: Double] = [:]
  private(set) var liveProgress: [Episode.ID: Double] = [:]

  var editMode: EditMode = .inactive {
    didSet {
      if !editMode.isEditing {
        selectedEpisodeIDs.removeAll()
      }
    }
  }

  var selectedEpisodeIDs: Set<Episode.ID> = []

  var entries: [Entry] {
    episodes.map { episode in
      let activeProgress = liveProgress[episode.id]
      return Entry(
        episode: episode,
        progress: activeProgress ?? checkpointProgress[episode.id] ?? 0,
        isActive: activeProgress != nil
      )
    }
  }

  var allSelected: Bool {
    !entries.isEmpty && selectedEpisodeIDs.count == entries.count
  }

  var canMoveSelectedToTop: Bool {
    let current = transcriptionQueue.episodeIDs
    guard !selectedEpisodeIDs.isEmpty else { return false }
    return current != orderedSelectionFirst(in: current)
  }

  var canMoveSelectedToBottom: Bool {
    let current = transcriptionQueue.episodeIDs
    guard !selectedEpisodeIDs.isEmpty else { return false }
    return current != orderedSelectionLast(in: current)
  }

  func execute() async {
    await withDiscardingTaskGroup { group in
      group.addTask { [weak self] in
        guard let self else { return }
        await self.observeEpisodeIDs()
      }
      group.addTask { [weak self] in
        guard let self else { return }
        await self.observeLiveProgress()
      }
    }
  }

  func retry() {
    loadingState = .loading
    let episodeIDs = transcriptionQueue.episodeIDs
    Task { [weak self] in
      guard let self else { return }
      await self.load(episodeIDs)
    }
  }

  func selectAll() {
    selectedEpisodeIDs = Set(entries.map(\.id))
  }

  func deselectAll() {
    selectedEpisodeIDs.removeAll()
  }

  func move(fromOffsets: IndexSet, toOffset: Int) {
    let current = transcriptionQueue.episodeIDs
    let loadedEpisodeIDs = episodes.map(\.id)
    guard current == loadedEpisodeIDs else {
      Self.log.error(
        """
        Cannot drag stale transcription queue rows; \
        loadedEpisodes=\(loadedEpisodeIDs.count) queuedEpisodes=\(current.count)
        """
      )
      return
    }
    var reordered = current
    reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
    applyOrder(reordered)
  }

  func moveToTop(_ episodeID: Episode.ID) {
    let current = transcriptionQueue.episodeIDs
    guard let index = current.firstIndex(of: episodeID), index > current.startIndex else { return }
    var reordered = current
    let moved = reordered.remove(at: index)
    reordered.insert(moved, at: reordered.startIndex)
    applyOrder(reordered)
  }

  func moveToBottom(_ episodeID: Episode.ID) {
    let current = transcriptionQueue.episodeIDs
    guard
      let index = current.firstIndex(of: episodeID),
      index < current.index(before: current.endIndex)
    else {
      return
    }
    var reordered = current
    let moved = reordered.remove(at: index)
    reordered.append(moved)
    applyOrder(reordered)
  }

  func moveSelectedToTop() {
    applyOrder(orderedSelectionFirst(in: transcriptionQueue.episodeIDs))
  }

  func moveSelectedToBottom() {
    applyOrder(orderedSelectionLast(in: transcriptionQueue.episodeIDs))
  }

  func remove(_ episodeID: Episode.ID) {
    selectedEpisodeIDs.remove(episodeID)
    transcriptionProcessor.pause(episodeID)
  }

  func remove(at offsets: IndexSet) {
    let removedEpisodeIDs = offsets.compactMap { entries[safe: $0]?.id }
    for episodeID in removedEpisodeIDs {
      remove(episodeID)
    }
  }

  func removeSelected() {
    let removedEpisodeIDs = transcriptionQueue.episodeIDs.filter(selectedEpisodeIDs.contains)
    selectedEpisodeIDs.removeAll()
    for episodeID in removedEpisodeIDs {
      transcriptionProcessor.pause(episodeID)
    }
  }

  func canMoveToTop(_ episodeID: Episode.ID) -> Bool {
    transcriptionQueue.episodeIDs.first != episodeID
  }

  func canMoveToBottom(_ episodeID: Episode.ID) -> Bool {
    transcriptionQueue.episodeIDs.last != episodeID
  }

  private func observeEpisodeIDs() async {
    for await episodeIDs in transcriptionQueue.$episodeIDs.stream() {
      guard !Task.isCancelled else { return }
      if loadingState == .loaded {
        let loadedEpisodeIDs = episodes.map(\.id)
        if loadedEpisodeIDs == episodeIDs {
          continue
        }

        let episodesByID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
        if episodesByID.count == episodeIDs.count,
          episodeIDs.allSatisfy({ episodesByID[$0] != nil })
        {
          episodes = episodeIDs.compactMap { episodesByID[$0] }
          continue
        }
      }
      await load(episodeIDs)
    }
  }

  private func observeLiveProgress() async {
    var previousActiveEpisodeIDs = Set(transcriptionQueue.progress.keys)
    for await progress in transcriptionQueue.$progress.stream() {
      guard !Task.isCancelled else { return }
      let activeEpisodeIDs = Set(progress.keys)
      let pausedEpisodeIDs =
        previousActiveEpisodeIDs
        .subtracting(activeEpisodeIDs)
        .intersection(transcriptionQueue.episodeIDs)
      liveProgress = progress
      previousActiveEpisodeIDs = activeEpisodeIDs

      guard !pausedEpisodeIDs.isEmpty else { continue }
      do {
        let refreshed = try await loadCheckpointProgress(for: Array(pausedEpisodeIDs))
        guard !Task.isCancelled else { return }
        for (episodeID, value) in refreshed
        where transcriptionQueue.episodeIDs.contains(episodeID) && liveProgress[episodeID] == nil {
          checkpointProgress[episodeID] = value
        }
      } catch {
        Self.log.caughtError(
          "Failed to refresh \(pausedEpisodeIDs.count) paused transcription checkpoints",
          error
        )
      }
    }
  }

  private func load(_ episodeIDs: [Episode.ID]) async {
    guard transcriptionQueue.episodeIDs == episodeIDs else { return }
    do {
      async let loadedEpisodes = repo.podcastEpisodes(episodeIDs)
      async let loadedProgress = loadCheckpointProgress(for: episodeIDs)
      let (episodes, checkpointProgress) = try await (loadedEpisodes, loadedProgress)
      guard !Task.isCancelled else { return }
      guard transcriptionQueue.episodeIDs == episodeIDs else { return }

      self.episodes = episodes
      self.checkpointProgress = checkpointProgress
      liveProgress = transcriptionQueue.progress
      selectedEpisodeIDs.formIntersection(Set(episodes.map(\.id)))
      loadingState = .loaded
    } catch {
      guard !Task.isCancelled else { return }
      guard transcriptionQueue.episodeIDs == episodeIDs else { return }
      Self.log.caughtError(
        "Failed to load \(episodeIDs.count) transcription queue episodes",
        error
      )
      loadingState = .failed
    }
  }

  private func loadCheckpointProgress(
    for episodeIDs: [Episode.ID]
  ) async throws -> [Episode.ID: Double] {
    var loaded: [Episode.ID: Double] = [:]
    for episodeID in episodeIDs {
      try Task.checkCancellation()
      do {
        if let checkpoint = try await repo.transcriptionCheckpoint(episodeID) {
          loaded[episodeID] = checkpoint.progress
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        Self.log.caughtError(
          "Failed to load transcription checkpoint progress for episode \(episodeID)",
          error
        )
      }
    }
    return loaded
  }

  private func applyOrder(_ orderedEpisodeIDs: [Episode.ID]) {
    let current = transcriptionQueue.episodeIDs
    guard current != orderedEpisodeIDs else { return }
    guard transcriptionProcessor.reorder(orderedEpisodeIDs) else {
      Self.log.error("Transcription processor rejected queue reorder")
      return
    }

    let episodesByID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
    episodes = orderedEpisodeIDs.compactMap { episodesByID[$0] }
  }

  private func orderedSelectionFirst(in episodeIDs: [Episode.ID]) -> [Episode.ID] {
    episodeIDs.filter(selectedEpisodeIDs.contains)
      + episodeIDs.filter { !selectedEpisodeIDs.contains($0) }
  }

  private func orderedSelectionLast(in episodeIDs: [Episode.ID]) -> [Episode.ID] {
    episodeIDs.filter { !selectedEpisodeIDs.contains($0) }
      + episodeIDs.filter(selectedEpisodeIDs.contains)
  }
}
