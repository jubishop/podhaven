// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

extension Container {
  var silenceDiagnostics: Factory<SilenceDiagnostics> {
    Factory(self) { SilenceDiagnostics() }.scope(.cached)
  }
}

struct SilenceDiagnostics: Sendable {
  private struct History: Sendable {
    let sessionID = UUID()
    var runs = 0
    var backgroundRuns = 0
    var backgroundCompletedRuns = 0
    var completedRuns = 0
    var interruptedRuns = 0
    var expirations = 0
    var publishedFiles = 0
    var discardedAudioSeconds = 0.0
    var suppressedWarnings = 0
    var windowStart: ContinuousClock.Instant?
    var warnings = 0
    var retries: [String: Expiration] = [:]
  }

  struct Expiration: Sendable {
    let startedAt: ContinuousClock.Instant
    var runID: UUID
    var count: Int
    var discardedSeconds: Double
  }

  static let slowThreshold: Duration = .seconds(20)
  private static let window: Duration = .minutes(15)
  private static let warningLimit = 6
  private static let retryCapacity = 64

  private let history = ThreadSafe(History())

  fileprivate init() {}

  func startRun(id: UUID, background: Bool) -> SilenceAnalysisRun {
    history { history in
      history.runs += 1
      if background { history.backgroundRuns += 1 }
    }
    return SilenceAnalysisRun(id: id, background: background, diagnostics: self)
  }

  fileprivate func expiration(
    for generation: String,
    now: ContinuousClock.Instant,
    newRun: UUID? = nil,
    discardedSeconds: Double = 0
  ) -> Expiration? {
    history { history in
      history.retries = history.retries.filter { now - $0.value.startedAt < Self.window }
      guard let newRun else { return history.retries[generation] }
      var record =
        history.retries[generation]
        ?? Expiration(startedAt: now, runID: newRun, count: 0, discardedSeconds: 0)
      record.runID = newRun
      record.count += 1
      record.discardedSeconds += discardedSeconds
      history.retries[generation] = record
      if history.retries.count > Self.retryCapacity,
        let oldest = history.retries.min(by: { $0.value.startedAt < $1.value.startedAt })
      {
        history.retries[oldest.key] = nil
      }
      return record
    }
  }

  fileprivate func finish(
    outcome: SilenceAnalysisRun.Outcome,
    background: Bool,
    expired: Bool,
    publishedFiles: Int,
    discardedSeconds: Double
  ) {
    history { history in
      if outcome == .completed { history.completedRuns += 1 }
      if background && outcome == .completed { history.backgroundCompletedRuns += 1 }
      if outcome == .interrupted { history.interruptedRuns += 1 }
      if expired { history.expirations += 1 }
      history.publishedFiles += publishedFiles
      history.discardedAudioSeconds += discardedSeconds
    }
  }

  fileprivate func summary(warning: Bool, now: ContinuousClock.Instant) -> (
    level: Logger.Level, fields: String
  ) {
    history { history in
      if history.windowStart == nil || now - (history.windowStart ?? now) >= Self.window {
        history.windowStart = now
        history.warnings = 0
      }
      let permitted = warning && history.warnings < Self.warningLimit
      if permitted { history.warnings += 1 }
      if warning && !permitted { history.suppressedWarnings += 1 }
      return (
        permitted ? .warning : .info,
        """
        sessionID=\(history.sessionID) sessionRuns=\(history.runs) \
        sessionBackgroundRuns=\(history.backgroundRuns) \
        sessionBackgroundCompletedRuns=\(history.backgroundCompletedRuns) \
        sessionCompletedRuns=\(history.completedRuns) \
        sessionInterruptedRuns=\(history.interruptedRuns) \
        sessionExpirations=\(history.expirations) \
        sessionPublishedFiles=\(history.publishedFiles) \
        sessionDiscardedAudioSeconds=\(history.discardedAudioSeconds) \
        suppressedWarnings=\(history.suppressedWarnings) warningSuppressed=\(warning && !permitted)
        """
      )
    }
  }
}

final class SilenceAnalysisRun: Sendable {
  enum StopReason: String, Sendable {
    case drained
    case backgroundExpiration
    case lifecycle
    case thermal
    case eligibility
    case cancelled
    case failure
  }

  enum Outcome: String, Sendable {
    case running
    case completed
    case interrupted
    case failed
    case deferred
  }

  enum AttemptOutcome: String, Sendable {
    case running
    case published
    case stale
    case failed
    case interrupted
  }

  private struct Attempt: Sendable {
    let id = UUID()
    let filename: String
    let generation: String
    let startedAt: ContinuousClock.Instant
    var processedSeconds = 0.0
    var totalSeconds: Double?
    var checkpointSeconds = 0.0
    var outcome = AttemptOutcome.running
  }

  private struct State: Sendable {
    enum SlowReport: Sendable {
      case pending
      case recorded
    }

    enum BackgroundExpiration: Sendable {
      case absent
      case observed
    }

    var attempt: Attempt?
    var outcome = Outcome.running
    var stopReason: StopReason?
    var interruptionThermal: ThermalPressure?
    var processedSeconds = 0.0
    var discardedSeconds = 0.0
    var completedFiles = 0
    var publishedFiles = 0
    var failedFiles = 0
    var slowReport = SlowReport.pending
    var transcriptionObserved = false
    var embeddingObserved = false
    var expiration: SilenceDiagnostics.Expiration?
    var previousExpiredRunID: UUID?
    var backgroundExpiration = BackgroundExpiration.absent
  }

  private static let log = Log.as("SilenceDiagnostics")
  private let id: UUID
  let background: Bool
  private let diagnostics: SilenceDiagnostics
  private let clockNow = Container.shared.continuousClockNow()
  private let cpuTime = Container.shared.processCPUTime()
  private let sharedState = Container.shared.sharedState()
  private let transcription = Container.shared.transcriptionProcessor()
  private let embedding = Container.shared.embeddingProcessor()
  private let startedAt: ContinuousClock.Instant
  private let startCPU: ProcessCPUTime
  private let startThermal: ThermalPressure
  private let priority: UInt8
  private let state = ThreadSafe(State())

  fileprivate init(id: UUID, background: Bool, diagnostics: SilenceDiagnostics) {
    self.id = id
    self.background = background
    self.diagnostics = diagnostics
    startedAt = clockNow()
    startCPU = cpuTime()
    startThermal = sharedState.thermalPressure
    priority = Task.currentPriority.rawValue
    observeConcurrentWork()
  }

  func beginAttempt(filename: String, generation: String) {
    let now = clockNow()
    let prior = diagnostics.expiration(for: generation, now: now)
    state { state in
      state.attempt = Attempt(filename: filename, generation: generation, startedAt: now)
      state.expiration = prior
      state.previousExpiredRunID = prior?.runID
    }
    emit(event: "silenceAttemptStarted", now: now, warning: false)
  }

  func progress(processedSeconds: Double, totalSeconds: Double) {
    let checkpoint = state { state in
      guard var attempt = state.attempt, attempt.outcome == .running else { return false }
      let seconds = min(totalSeconds, max(attempt.processedSeconds, processedSeconds))
      state.processedSeconds += seconds - attempt.processedSeconds
      attempt.processedSeconds = seconds
      attempt.totalSeconds = totalSeconds
      let checkpoint = seconds - attempt.checkpointSeconds >= 1
      if checkpoint { attempt.checkpointSeconds = seconds }
      state.attempt = attempt
      return checkpoint
    }
    if checkpoint { reportSlowRunIfNeeded() }
  }

  func interrupt(_ reason: StopReason) {
    let thermal = sharedState.thermalPressure
    observeConcurrentWork()
    state { state in
      guard state.stopReason == nil else { return }
      state.stopReason = reason
      state.interruptionThermal = thermal
    }
  }

  func finishAttempt(_ outcome: AttemptOutcome) {
    state { state in
      guard var attempt = state.attempt, attempt.outcome == .running else { return }
      attempt.outcome = outcome
      state.attempt = attempt
      switch outcome {
      case .published:
        state.completedFiles += 1
        state.publishedFiles += 1
      case .stale:
        state.completedFiles += 1
        state.discardedSeconds += attempt.processedSeconds
      case .failed:
        state.failedFiles += 1
        state.discardedSeconds += attempt.processedSeconds
      case .interrupted:
        state.discardedSeconds += attempt.processedSeconds
      case .running:
        break
      }
    }
    reportSlowRunIfNeeded()
    emit(event: "silenceAttemptFinished", now: clockNow(), warning: false)
  }

  func finish(expired: Bool) {
    let before = state()
    guard before.outcome == .running else { return }
    if expired && before.stopReason == nil { interrupt(.backgroundExpiration) }
    if let attempt = state().attempt, attempt.outcome == .running {
      finishAttempt(.interrupted)
    }
    let now = clockNow()
    let snapshot = state()
    let outcome: Outcome
    switch snapshot.stopReason {
    case .failure: outcome = .failed
    case .thermal where snapshot.attempt == nil: outcome = .deferred
    case .none, .drained: outcome = .completed
    default: outcome = .interrupted
    }
    var expiration = snapshot.expiration
    if expired, let attempt = snapshot.attempt, attempt.outcome == .interrupted {
      expiration = diagnostics.expiration(
        for: attempt.generation,
        now: now,
        newRun: id,
        discardedSeconds: attempt.processedSeconds
      )
    }
    state { state in
      state.outcome = outcome
      state.expiration = expiration
      state.backgroundExpiration = expired ? .observed : .absent
    }
    diagnostics.finish(
      outcome: outcome,
      background: background,
      expired: expired,
      publishedFiles: snapshot.publishedFiles,
      discardedSeconds: snapshot.discardedSeconds
    )
    let warning =
      now - startedAt >= SilenceDiagnostics.slowThreshold
      || (snapshot.stopReason == .thermal && snapshot.discardedSeconds > 0)
      || (expired && (expiration?.count ?? 0) >= 3)
    emit(event: "silenceRunFinished", now: now, warning: warning)
  }

  private func observeConcurrentWork() {
    let transcribing = transcription.isTranscribing
    let computing = embedding.isComputing
    state { state in
      state.transcriptionObserved = state.transcriptionObserved || transcribing
      state.embeddingObserved = state.embeddingObserved || computing
    }
  }

  private func reportSlowRunIfNeeded() {
    observeConcurrentWork()
    let now = clockNow()
    guard now - startedAt >= SilenceDiagnostics.slowThreshold else { return }
    let report = state { state in
      guard state.slowReport == .pending else { return false }
      state.slowReport = .recorded
      return true
    }
    if report { emit(event: "silenceRunSlow", now: now, warning: true) }
  }

  private func emit(event: String, now: ContinuousClock.Instant, warning: Bool) {
    observeConcurrentWork()
    let snapshot = state()
    let aggregate = diagnostics.summary(warning: warning, now: now)
    let attempt = snapshot.attempt
    let totalSeconds: String
    if let duration = attempt?.totalSeconds {
      totalSeconds = String(duration)
    } else {
      totalSeconds = "unknown"
    }
    let attemptWallSeconds: Double
    if let start = attempt?.startedAt {
      attemptWallSeconds = (now - start).asTimeInterval
    } else {
      attemptWallSeconds = 0
    }
    Self.log.log(
      level: aggregate.level,
      """
      event=\(event) runID=\(id) attemptID=\(attempt?.id.uuidString ?? "none") \
      file=\(attempt?.filename ?? "none") generation=\(attempt?.generation ?? "none") \
      mode=\(background ? "background" : "foreground") taskPriority=\(priority) \
      wallSeconds=\((now - startedAt).asTimeInterval) attemptWallSeconds=\(attemptWallSeconds) \
      processedAudioSeconds=\(snapshot.processedSeconds) \
      attemptAudioSeconds=\(attempt?.processedSeconds ?? 0) totalAudioSeconds=\(totalSeconds) \
      completedFiles=\(snapshot.completedFiles) publishedFiles=\(snapshot.publishedFiles) \
      failedFiles=\(snapshot.failedFiles) discardedAudioSeconds=\(snapshot.discardedSeconds) \
      outcome=\(snapshot.outcome.rawValue) attemptOutcome=\(attempt?.outcome.rawValue ?? "none") \
      stopReason=\(snapshot.stopReason?.rawValue ?? (snapshot.outcome == .completed ? "drained" : "none")) \
      backgroundExpired=\(snapshot.backgroundExpiration == .observed) \
      thermal=\(sharedState.thermalPressure.rawValue) startThermal=\(startThermal.rawValue) \
      interruptionThermal=\(snapshot.interruptionThermal?.rawValue ?? "none") \
      transcriptionActive=\(transcription.isTranscribing) embeddingActive=\(embedding.isComputing) \
      transcriptionObserved=\(snapshot.transcriptionObserved) embeddingObserved=\(snapshot.embeddingObserved) \
      processCPUSeconds=\(cpuTime().elapsed(since: startCPU)) cpuScope=process \
      expirationCount=\(snapshot.expiration?.count ?? 0) \
      expirationDiscardedSeconds=\(snapshot.expiration?.discardedSeconds ?? 0) \
      previousExpiredRunID=\(snapshot.previousExpiredRunID?.uuidString ?? "none") \
      \(aggregate.fields)
      """
    )
  }
}
