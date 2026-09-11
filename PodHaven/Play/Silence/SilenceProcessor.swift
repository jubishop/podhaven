// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging
import SwiftUI
import Tagged

extension Container {
  var silenceProcessor: Factory<SilenceProcessor> {
    Factory(self) { SilenceProcessor() }.scope(.cached)
  }
}

actor SilenceProcessor {
  private static let log = Log.as("SilenceProcessor")
  private let store = Container.shared.silenceStore()
  private let state = Container.shared.sharedState()
  private let settings = Container.shared.userSettings()
  private nonisolated let demand = ThreadSafe(false)
  private nonisolated let scheduler: BackgroundTaskScheduler
  private var observations: [Task<Void, Never>] = []
  private var worker: Task<Void, Never>?
  private var owner: UUID?
  private var candidates: [SilenceCandidate] = []
  private var scenePhase = ScenePhase.background
  private var currentFilename: String?
  private var diagnosticRun: SilenceAnalysisRun?

  fileprivate init() {
    let demand = self.demand
    scheduler = BackgroundTaskScheduler(
      identifier: "\(AppInfo.bundleIdentifier).silenceAnalysis",
      cadence: .minutes(1),
      taskType: .processing(requiresNetworkConnectivity: false),
      schedulingMode: .onDemand { demand() },
      expirationBehavior: .awaitCancellation
    )
  }

  deinit {
    for observation in observations { observation.cancel() }
    worker?.cancel()
  }

  nonisolated func register() {
    scheduler.register { [weak self] complete, context in
      guard let self else {
        complete(false)
        return
      }
      do {
        try await self.drain(background: true, context: context)
        complete(true)
      } catch {
        Self.log.caughtError("Background silence analysis stopped", error)
        complete(false)
      }
    }
    Task { [weak self] in await self?.start() }
  }

  nonisolated func handleScenePhaseChange(to phase: ScenePhase) {
    Task { [weak self] in await self?.setScenePhase(phase) }
  }

  private func start() {
    guard observations.isEmpty else { return }
    let store = self.store
    let state = self.state
    let settings = self.settings
    observations = [
      Task { [weak self] in
        do {
          try await store.pruneOrphans()
        } catch {
          Self.log.caughtError("Silence cache cleanup failed", error)
        }
        do {
          for try await candidates in store.candidates() {
            guard let self, !Task.isCancelled else { return }
            await self.setCandidates(candidates)
          }
        } catch {
          Self.log.caughtError("Silence eligibility observation failed", error)
        }
      },
      Task { [weak self] in
        for await _ in state.$thermalPressure.stream() {
          guard let self, !Task.isCancelled else { return }
          await self.reconcile()
        }
      },
      Task { [weak self] in
        for await _ in settings.$silenceMode.stream() {
          guard let self, !Task.isCancelled else { return }
          await self.reconcile()
        }
      },
      Task { [weak self] in
        for await _ in state.$silenceOverride.stream() {
          guard let self, !Task.isCancelled else { return }
          await self.reconcile()
        }
      },
      Task { [weak self] in
        for await _ in state.$currentEpisodeID.stream() {
          guard let self, !Task.isCancelled else { return }
          await self.reconcile()
        }
      },
    ]
  }

  private func setCandidates(_ candidates: [SilenceCandidate]) {
    self.candidates = candidates
    reconcile()
  }

  private func setScenePhase(_ phase: ScenePhase) {
    scenePhase = phase
    reconcile()
  }

  private var eligible: [SilenceCandidate] {
    candidates.filter { candidate in
      var temporary: SilenceMode?
      if let override = state.silenceOverride,
        override.episodeID == state.currentEpisodeID, override.episodeID == candidate.episodeID
      {
        temporary = override.mode
      }
      return SilenceMode.resolve(
        temporary: temporary,
        podcast: candidate.podcastMode,
        global: settings.silenceMode
      ) != .off
    }
    .sorted { lhs, rhs in
      if (lhs.episodeID == state.currentEpisodeID) != (rhs.episodeID == state.currentEpisodeID) {
        return lhs.episodeID == state.currentEpisodeID
      }
      return (lhs.queueOrder ?? Int.max, lhs.episodeID.rawValue)
        < (rhs.queueOrder ?? Int.max, rhs.episodeID.rawValue)
    }
  }

  private func reconcile() {
    let eligible = eligible
    demand(!eligible.isEmpty)
    if let currentFilename, !eligible.contains(where: { $0.filename == currentFilename }) {
      diagnosticRun?.interrupt(.eligibility)
      worker?.cancel()
      scheduler.cancelRunningTasks()
    }
    guard state.thermalPressure.permitsDiscretionaryWork, scenePhase == .active else {
      if !state.thermalPressure.permitsDiscretionaryWork {
        diagnosticRun?.interrupt(.thermal)
      } else if diagnosticRun?.background == false {
        diagnosticRun?.interrupt(.lifecycle)
      }
      worker?.cancel()
      if !state.thermalPressure.permitsDiscretionaryWork { scheduler.cancelRunningTasks() }
      scheduler.scheduleNext()
      return
    }
    guard worker == nil, owner == nil, !eligible.isEmpty else { return }
    worker = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.drain(background: false)
      } catch {
        Self.log.caughtError("Foreground silence analysis stopped", error)
        if !(error is CancellationError) { self.demand(false) }
      }
      await self.finishedWorker()
    }
  }

  private func finishedWorker() {
    worker = nil
    if demand(), scenePhase == .active, state.thermalPressure.permitsDiscretionaryWork {
      reconcile()
    }
  }

  private func drain(
    background: Bool,
    context: BackgroundTaskScheduler.ExecutionContext? = nil
  ) async throws {
    guard owner == nil else { return }
    let id = UUID()
    owner = id
    let diagnostics = Container.shared.silenceDiagnostics().startRun(id: id, background: background)
    diagnosticRun = diagnostics
    defer {
      if Task.isCancelled {
        diagnostics.interrupt(context?.isExpired == true ? .backgroundExpiration : .cancelled)
      } else if !state.thermalPressure.permitsDiscretionaryWork {
        diagnostics.interrupt(.thermal)
      } else if !background && scenePhase != .active {
        diagnostics.interrupt(.lifecycle)
      }
      diagnostics.finish(expired: context?.isExpired ?? false)
      diagnosticRun = nil
      owner = nil
      currentFilename = nil
      if background && scenePhase == .active { reconcile() }
    }
    do {
      try await analyzeEligibleFiles(background: background, diagnostics: diagnostics)
    } catch {
      if !(error is CancellationError) { diagnostics.interrupt(.failure) }
      throw error
    }
  }

  private func analyzeEligibleFiles(background: Bool, diagnostics: SilenceAnalysisRun) async throws
  {
    var checked: Set<String> = []
    while state.thermalPressure.permitsDiscretionaryWork && (background || scenePhase == .active) {
      try Task.checkCancellation()
      var selected: CachedAudioContent?
      for candidate in eligible {
        guard let content = try await store.content(for: candidate.filename),
          !checked.contains(content.generation)
        else { continue }
        checked.insert(content.generation)
        guard content.failureCount < 2 else { continue }
        do {
          if try content.map != nil { continue }
        } catch {
          Self.log.caughtError("Discarding invalid silence map for \(content.filename)", error)
        }
        selected = content
        break
      }
      guard let content = selected else {
        demand(false)
        return
      }
      currentFilename = content.filename
      let started = ContinuousClock.now
      diagnostics.beginAttempt(filename: content.filename, generation: content.generation)
      do {
        let url = CacheManager.resolveCachedFilepath(for: content.filename).rawValue
        let map = try await SilenceAnalyzer.analyze(url) { processedSeconds, totalSeconds in
          diagnostics.progress(processedSeconds: processedSeconds, totalSeconds: totalSeconds)
        }
        try Task.checkCancellation()
        let published = try await store.publish(map, for: content)
        diagnostics.finishAttempt(published ? .published : .stale)
        Self.log.info(
          "Silence analysis file=\(content.filename) published=\(published) intervals=\(map.intervals.count) duration=\(started.duration(to: .now))"
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        diagnostics.finishAttempt(.failed)
        Self.log.caughtError("Silence analysis failed for \(content.filename)", error)
        try await store.recordFailure(for: content)
      }
      currentFilename = nil
    }
  }
}
