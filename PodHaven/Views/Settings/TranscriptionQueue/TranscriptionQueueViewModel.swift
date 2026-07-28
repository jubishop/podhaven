// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import SwiftUI

@Observable @MainActor final class TranscriptionQueueViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
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

  private enum QueueMutation {
    struct Removal {
      let episodeIDs: [Episode.ID]
      let selectedEpisodeIDs: Set<Episode.ID>
    }

    case reorder([Episode.ID])
    case remove(Removal)
  }

  @ObservationIgnored private var mutationTask: Task<Void, Never>?
  @ObservationIgnored private var latestMutationID: UUID?
  @ObservationIgnored private var presentationRevision = UUID()

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
    let current = episodes.map(\.id)
    guard !selectedEpisodeIDs.isEmpty else { return false }
    return current != orderedSelectionFirst(in: current)
  }

  var canMoveSelectedToBottom: Bool {
    let current = episodes.map(\.id)
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
    let revision = presentationRevision
    Task { [weak self] in
      guard let self else { return }
      await self.load(episodeIDs, presentationRevision: revision)
    }
  }

  func selectAll() {
    selectedEpisodeIDs = Set(entries.map(\.id))
  }

  func deselectAll() {
    selectedEpisodeIDs.removeAll()
  }

  func move(fromOffsets: IndexSet, toOffset: Int) {
    let displayedEpisodeIDs = episodes.map(\.id)
    guard
      latestMutationID != nil
        || transcriptionQueue.episodeIDs == displayedEpisodeIDs
    else {
      Self.log.notice(
        """
        Cannot drag stale transcription queue rows; \
        loadedEpisodes=\(displayedEpisodeIDs.count) \
        queuedEpisodes=\(transcriptionQueue.episodeIDs.count)
        """
      )
      return
    }
    var reordered = displayedEpisodeIDs
    reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
    applyOrder(reordered)
  }

  func moveToTop(_ episodeID: Episode.ID) {
    let current = episodes.map(\.id)
    guard let index = current.firstIndex(of: episodeID), index > current.startIndex else { return }
    var reordered = current
    let moved = reordered.remove(at: index)
    reordered.insert(moved, at: reordered.startIndex)
    applyOrder(reordered)
  }

  func moveToBottom(_ episodeID: Episode.ID) {
    let current = episodes.map(\.id)
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
    applyOrder(orderedSelectionFirst(in: episodes.map(\.id)))
  }

  func moveSelectedToBottom() {
    applyOrder(orderedSelectionLast(in: episodes.map(\.id)))
  }

  func remove(_ episodeID: Episode.ID) {
    remove([episodeID])
  }

  func remove(at offsets: IndexSet) {
    let removedEpisodeIDs = offsets.compactMap { entries[safe: $0]?.id }
    remove(removedEpisodeIDs)
  }

  func removeSelected() {
    let removedEpisodeIDs = episodes.map(\.id).filter(selectedEpisodeIDs.contains)
    remove(removedEpisodeIDs)
  }

  func canMoveToTop(_ episodeID: Episode.ID) -> Bool {
    episodes.first?.id != episodeID
  }

  func canMoveToBottom(_ episodeID: Episode.ID) -> Bool {
    episodes.last?.id != episodeID
  }

  private func observeEpisodeIDs() async {
    for await episodeIDs in transcriptionQueue.$episodeIDs.stream() {
      guard !Task.isCancelled else { return }
      guard latestMutationID == nil else { continue }
      let revision = presentationRevision
      await reconcileEpisodes(episodeIDs, presentationRevision: revision)
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

  private func reconcileEpisodes(
    _ episodeIDs: [Episode.ID],
    presentationRevision revision: UUID
  ) async {
    guard
      latestMutationID == nil,
      presentationRevision == revision,
      transcriptionQueue.episodeIDs == episodeIDs
    else {
      return
    }
    if loadingState == .loaded {
      let loadedEpisodeIDs = episodes.map(\.id)
      if loadedEpisodeIDs == episodeIDs {
        return
      }

      let episodesByID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
      if episodesByID.count == episodeIDs.count,
        episodeIDs.allSatisfy({ episodesByID[$0] != nil })
      {
        episodes = episodeIDs.compactMap { episodesByID[$0] }
        selectedEpisodeIDs.formIntersection(Set(episodeIDs))
        return
      }
    }
    await load(episodeIDs, presentationRevision: revision)
  }

  private func load(
    _ episodeIDs: [Episode.ID],
    presentationRevision revision: UUID
  ) async {
    guard latestMutationID == nil, presentationRevision == revision else { return }
    guard transcriptionQueue.episodeIDs == episodeIDs else { return }
    do {
      async let loadedEpisodes = repo.podcastEpisodes(episodeIDs)
      async let loadedProgress = loadCheckpointProgress(for: episodeIDs)
      let (episodes, checkpointProgress) = try await (loadedEpisodes, loadedProgress)
      guard !Task.isCancelled else { return }
      guard latestMutationID == nil, presentationRevision == revision else { return }
      guard transcriptionQueue.episodeIDs == episodeIDs else { return }

      self.episodes = episodes
      self.checkpointProgress = checkpointProgress
      liveProgress = transcriptionQueue.progress
      selectedEpisodeIDs.formIntersection(Set(episodes.map(\.id)))
      loadingState = .loaded
    } catch {
      guard !Task.isCancelled else { return }
      guard latestMutationID == nil, presentationRevision == revision else { return }
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
    let current = episodes.map(\.id)
    guard current != orderedEpisodeIDs else { return }

    let episodesByID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
    guard
      episodesByID.count == orderedEpisodeIDs.count,
      orderedEpisodeIDs.allSatisfy({ episodesByID[$0] != nil })
    else {
      Self.log.notice("Cannot optimistically project a stale transcription queue reorder")
      return
    }
    episodes = orderedEpisodeIDs.compactMap { episodesByID[$0] }
    enqueueMutation(.reorder(orderedEpisodeIDs))
  }

  private func remove(_ episodeIDs: [Episode.ID]) {
    guard !episodeIDs.isEmpty else { return }
    let requestedEpisodeIDs = Set(episodeIDs)
    let removedEpisodeIDs = episodes.map(\.id).filter(requestedEpisodeIDs.contains)
    guard !removedEpisodeIDs.isEmpty else { return }

    let removedEpisodeIDSet = Set(removedEpisodeIDs)
    let removedSelectedEpisodeIDs = selectedEpisodeIDs.intersection(removedEpisodeIDSet)
    episodes.removeAll { removedEpisodeIDSet.contains($0.id) }
    selectedEpisodeIDs.subtract(removedEpisodeIDSet)
    enqueueMutation(
      .remove(
        QueueMutation.Removal(
          episodeIDs: removedEpisodeIDs,
          selectedEpisodeIDs: removedSelectedEpisodeIDs
        )
      )
    )
  }

  private func enqueueMutation(_ mutation: QueueMutation) {
    let previousTask = mutationTask
    let mutationID = UUID()
    latestMutationID = mutationID
    presentationRevision = mutationID
    mutationTask = Task { [weak self, previousTask] in
      if let previousTask {
        await previousTask.value
      }
      guard let self else { return }
      await self.performMutation(mutation)
      await self.finishMutation(mutationID)
    }
  }

  private func performMutation(_ mutation: QueueMutation) async {
    switch mutation {
    case .reorder(let orderedEpisodeIDs):
      do {
        guard try await transcriptionProcessor.reorder(orderedEpisodeIDs) else {
          Self.log.notice("Transcription processor rejected queue reorder")
          return
        }
      } catch {
        Self.log.caughtError("Failed to reorder transcription queue", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    case .remove(let removal):
      await performRemoval(removal)
    }
  }

  private func performRemoval(_ removal: QueueMutation.Removal) async {
    var firstRemarkableError: (any Error)?
    for episodeID in removal.episodeIDs {
      do {
        try await transcriptionProcessor.pause(episodeID)
      } catch {
        if removal.selectedEpisodeIDs.contains(episodeID) {
          selectedEpisodeIDs.insert(episodeID)
        }
        Self.log.caughtError(
          "Failed to remove transcription \(episodeID) from the queue",
          error
        )
        if firstRemarkableError == nil, ErrorKit.isRemarkable(error) {
          firstRemarkableError = error
        }
      }
    }
    if let firstRemarkableError {
      alert(ErrorKit.message(for: firstRemarkableError))
    }
  }

  private func finishMutation(_ mutationID: UUID) async {
    guard latestMutationID == mutationID else { return }
    latestMutationID = nil
    mutationTask = nil
    await reconcileEpisodes(
      transcriptionQueue.episodeIDs,
      presentationRevision: presentationRevision
    )
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
