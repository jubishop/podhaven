// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  var embeddingWorkDemand: Factory<EmbeddingWorkDemand> {
    Factory(self) {
      EmbeddingWorkDemand(
        pipelineVersion: EmbeddingPipelineVersion(
          embeddingRevision: self.contextualEmbedding().revision,
          recipeVersion: EmbeddingService.recipeVersion
        ),
        now: self.dateProvider().now,
        store: self.standardDefaults()
      )
    }
    .scope(.cached)
  }
}

struct EmbeddingPipelineVersion: Codable, Equatable, Sendable {
  let embeddingRevision: Int
  let recipeVersion: Int
}

struct EmbeddingWorkDemand: Sendable {
  struct Snapshot: Sendable {
    let generation: Int
    let fullRefreshStartedAt: Date?

    var requiresFullRefresh: Bool {
      fullRefreshStartedAt != nil
    }
  }

  private enum Status: String, Codable, Sendable {
    case idle
    case pending
  }

  private struct FullRefresh: Codable, Equatable, Sendable {
    let pipelineVersion: EmbeddingPipelineVersion
    let startedAt: Date
  }

  private struct State: Codable, DefaultsStorable {
    var generation = 0
    var status = Status.idle
    var completedPipelineVersion: EmbeddingPipelineVersion?
    var fullRefresh: FullRefresh?
  }

  private static let key = "embeddingWorkDemand"

  private let pipelineVersion: EmbeddingPipelineVersion
  @PersistedThreadSafe private var state: State

  fileprivate init(
    pipelineVersion: EmbeddingPipelineVersion,
    now: Date,
    store: any KeyValueStore
  ) {
    self.pipelineVersion = pipelineVersion
    _state = PersistedThreadSafe(
      wrappedValue: State(),
      Self.key,
      store: store
    )

    $state.update { state in
      if state.completedPipelineVersion != pipelineVersion {
        if state.fullRefresh?.pipelineVersion != pipelineVersion {
          state.fullRefresh = FullRefresh(
            pipelineVersion: pipelineVersion,
            startedAt: now
          )
        }
        state.generation += 1
        state.status = .pending
      } else if state.fullRefresh != nil {
        state.fullRefresh = nil
      }
    }
  }

  var hasWork: Bool {
    state.status == .pending
  }

  func snapshot() -> Snapshot {
    let currentState = state
    return Snapshot(
      generation: currentState.generation,
      fullRefreshStartedAt: currentState.fullRefresh?.startedAt
    )
  }

  func markAvailable() {
    $state.update { state in
      state.generation += 1
      state.status = .pending
    }
  }

  func ensureAvailable() {
    $state.update { state in
      guard state.status == .idle else { return }
      state.generation += 1
      state.status = .pending
    }
  }

  func markPipelineRefreshCompleted() {
    $state.update { state in
      guard
        state.completedPipelineVersion != pipelineVersion || state.fullRefresh != nil
      else { return }
      state.completedPipelineVersion = pipelineVersion
      state.fullRefresh = nil
    }
  }

  @discardableResult
  func clear(ifUnchanged snapshot: Snapshot) -> Bool {
    $state.update { state in
      guard state.generation == snapshot.generation else { return false }
      state.status = .idle
      state.completedPipelineVersion = pipelineVersion
      state.fullRefresh = nil
      return true
    }
  }
}
