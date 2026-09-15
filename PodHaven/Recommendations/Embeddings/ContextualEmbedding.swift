// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import NaturalLanguage

// MARK: - Container

extension Container {
  var contextualEmbedding: Factory<ContextualEmbedding> {
    Factory(self) { ContextualEmbedding(embedding: self.nlContextualEmbedding()) }
      .scope(.cached)
  }
}

// MARK: - Errors

enum EmbeddingError: LocalizedError {
  case modelUnavailable
  case noResult

  var errorDescription: String? {
    switch self {
    case .modelUnavailable:
      "Contextual embedding model is not available"
    case .noResult:
      "Embedding produced no token vectors for the given text"
    }
  }
}

// MARK: - ContextualEmbedding

// Actor so the synchronous NLContextualEmbedding work (BNNS-heavy
// embeddingResult, asset load) runs on the actor's executor instead of
// being pinned to a @MainActor caller's executor via the non-Sendable
// parameter.
actor ContextualEmbedding {
  @DynamicInjected(\.continuousClockNow) private var continuousClockNow

  private static let log = Log.as(LogSubsystem.Recommendations.embedding)
  private static let recoveryCooldown: Duration = .seconds(60)

  private enum AssetState {
    case idle
    case requesting(AssetRequest)
    case requested(AssetRequest)
    case loading
    case needsRecovery
    case retryable
    case usable

    var name: String {
      switch self {
      case .idle: "idle"
      case .requesting: "requesting"
      case .requested: "requested"
      case .loading: "loading"
      case .needsRecovery: "needsRecovery"
      case .retryable: "retryable"
      case .usable: "usable"
      }
    }
  }

  private struct AssetRequest {
    enum Kind: String {
      case initial
      case recovery
    }

    let id = UUID()
    let kind: Kind
    let startedAt: ContinuousClock.Instant
  }

  nonisolated let assetsLoaded = AsyncLatch<Void>()
  nonisolated let revision: Int

  private let embedding: any Embeddable
  private let modelSession = UUID()
  private var state: AssetState = .idle
  private var attemptedActivation: UUID?
  private var lastAttemptStartedAt: ContinuousClock.Instant?
  private var firstFailureAt: ContinuousClock.Instant?
  private var permitsPreparation: @Sendable () -> Bool = { false }
  private var loadAttempts = 0
  private var requestAttempts = 0

  init(embedding: sending any Embeddable) {
    self.embedding = embedding
    revision = embedding.revision
  }

  func requestAndLoadAssetsIfNeeded(
    activation: UUID = UUID(),
    permitsPreparation: @escaping @Sendable () -> Bool = { true }
  ) {
    guard !Task.isCancelled, permitsPreparation(), !assetsLoaded.isOpen else { return }
    self.permitsPreparation = permitsPreparation

    switch state {
    case .requesting:
      attemptedActivation = activation
      return
    case .requested(let request):
      attemptedActivation = activation
      loadRequestedAssets(request)
      return
    case .needsRecovery:
      attemptedActivation = activation
      requestAssets(kind: .recovery)
      return
    case .loading, .usable:
      return
    case .idle, .retryable:
      break
    }

    guard attemptedActivation != activation else { return }
    attemptedActivation = activation
    let now = continuousClockNow()
    if let lastAttemptStartedAt, now - lastAttemptStartedAt < Self.recoveryCooldown {
      Self.log.debug("Contextual embedding preparation deferred for cooldown")
      return
    }
    lastAttemptStartedAt = now

    if embedding.hasAvailableAssets {
      loadAssets(recovering: false)
      if case .needsRecovery = state { requestAssets(kind: .recovery) }
    } else {
      requestAssets(kind: .initial)
    }
  }

  // Load on-disk assets without triggering a download. Safe from a
  // BG-launched task handler where the scene never went active.
  func loadAssetsIfAvailable() {
    guard !Task.isCancelled, !assetsLoaded.isOpen, embedding.hasAvailableAssets else { return }
    guard case .idle = state else { return }
    loadAssets(recovering: false)
  }

  func vector(for text: String) throws -> [Float] {
    guard assetsLoaded.isOpen else { throw EmbeddingError.modelUnavailable }

    let result = try embedding.embeddingResult(for: text)

    // Pool subword vectors by averaging
    var sum: [Float]?
    var count = 0

    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
      if var accumulated = sum {
        for i in 0..<vector.count { accumulated[i] += Float(vector[i]) }
        sum = accumulated
      } else {
        sum = vector.map { Float($0) }
      }
      count += 1
      return true
    }

    guard count > 0, let sum else { throw EmbeddingError.noResult }
    return sum.map { $0 / Float(count) }
  }

  private func loadAssets(recovering: Bool) {
    let prior = state.name
    let startedAt = continuousClockNow()
    state = .loading
    loadAttempts += 1

    do {
      try embedding.load()
    } catch {
      firstFailureAt = firstFailureAt ?? continuousClockNow()
      state = recovering ? .retryable : .needsRecovery
      Self.log.caughtError(
        """
        Failed to load contextual embedding \(diagnostics) priorState=\(prior) \
        operation=load recovering=\(recovering) loadSeconds=\((continuousClockNow() - startedAt).asTimeInterval)
        """,
        error
      )
      return
    }

    state = .usable
    if let firstFailureAt {
      Self.log.warning(
        """
        Contextual embedding recovered event=contextualEmbeddingRecovered \(diagnostics) \
        wallSeconds=\((continuousClockNow() - firstFailureAt).asTimeInterval)
        """
      )
    } else {
      Self.log.info("Contextual embedding loaded \(diagnostics)")
    }
    assetsLoaded.open()
  }

  private func requestAssets(kind: AssetRequest.Kind) {
    guard permitsPreparation() else { return }
    let request = AssetRequest(kind: kind, startedAt: continuousClockNow())
    lastAttemptStartedAt = request.startedAt
    state = .requesting(request)
    requestAttempts += 1
    Self.log.info(
      "Requesting contextual embedding assets \(diagnostics) operation=\(kind.rawValue)"
    )
    embedding.requestAssets { [weak self] result, error in
      Task { [weak self] in
        await self?.completeAssetRequest(request: request, result: result, error: error)
      }
    }
  }

  private func completeAssetRequest(
    request: AssetRequest,
    result: NLContextualEmbedding.AssetsResult,
    error: (any Error)?
  ) {
    guard case .requesting(let current) = state, current.id == request.id else { return }
    state = result == .available && error == nil ? .requested(request) : .retryable
    let context = """
      event=contextualEmbeddingAssetRequestCompleted \(diagnostics) \
      priorState=requesting operation=\(request.kind.rawValue) result=\(result.rawValue) \
      requestSeconds=\((continuousClockNow() - request.startedAt).asTimeInterval)
      """
    if let error {
      firstFailureAt = firstFailureAt ?? continuousClockNow()
      let nsError = error as NSError
      let isAssetTimeout =
        nsError.domain == "NLNaturalLanguageErrorDomain" && nsError.code == 7
        && nsError.localizedDescription == "Asset download request timed out"
      Self.log.caughtError(
        "Failed to download contextual embedding assets \(context)",
        error,
        level: isAssetTimeout ? .warning : .error
      )
      return
    }

    switch result {
    case .available:
      Self.log.info("Contextual embedding assets available \(context)")
      loadRequestedAssets(request)
    case .notAvailable:
      firstFailureAt = firstFailureAt ?? continuousClockNow()
      Self.log.warning("Contextual embedding assets not available \(context)")
    case .error:
      firstFailureAt = firstFailureAt ?? continuousClockNow()
      Self.log.error("Contextual embedding asset request failed without an error object \(context)")
    @unknown default:
      firstFailureAt = firstFailureAt ?? continuousClockNow()
      Self.log.error("Unknown contextual embedding asset request result \(context)")
    }
  }

  private func loadRequestedAssets(_ request: AssetRequest) {
    guard permitsPreparation() else { return }
    loadAssets(recovering: request.kind == .recovery)
    if case .needsRecovery = state { requestAssets(kind: .recovery) }
  }

  private var diagnostics: String {
    """
    modelSession=\(modelSession) revision=\(revision) assetsAvailable=\(embedding.hasAvailableAssets) \
    state=\(state.name) loadAttempts=\(loadAttempts) requestAttempts=\(requestAttempts)
    """
  }
}
