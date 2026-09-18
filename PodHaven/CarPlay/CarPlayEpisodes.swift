// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import Foundation
import GRDB
import Logging

extension Container {
  @MainActor var carPlayEpisodes: Factory<CarPlayEpisodes> {
    Factory(self) { CarPlayEpisodes() }
  }
}

@MainActor
final class CarPlayEpisodes {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.smartListRepo) private var smartListRepo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings
  private static let log = Log.as("CarPlayEpisodes")
  private var catalog = CarPlaySmartListHub.Content.loading
  private var definitions: [SmartList] = []
  private var counts: [SmartList.ID: Int] = [:]
  private var root: CarPlaySmartListHub?
  private var replacements: [CarPlaySmartListHub] = []
  private var details: [CarPlaySmartListDetail] = []
  private var visited: Set<SmartList.ID> = []
  private var selection: CarPlaySelection?
  private var catalogTask: Task<Void, Never>?
  private var unreadTask: Task<Void, Never>?
  private var stateTask: Task<Void, Never>?
  var canNavigate: (() -> Bool)?
  var navigate: ((CPListTemplate, Bool) -> Void)?
  var deleted: ((CPListTemplate) -> Void)?
  var restricted = false {
    didSet {
      renderCatalog()
      for detail in details { detail.restricted = restricted }
    }
  }

  fileprivate init() {}

  func start(_ template: CPListTemplate, selection: CarPlaySelection) {
    self.selection = selection
    root = makeHub(template, reset: false)
    observeCatalog()
    stateTask = Task { [weak self] in
      guard let self else { return }
      await withDiscardingTaskGroup { group in
        group.addTask { await self.observeCurrentID() }
        group.addTask { await self.observePlayback() }
        group.addTask { await self.observeOnDeck() }
        group.addTask { await self.observeTimeFormat() }
      }
    }
  }

  private func observeCurrentID() async {
    for await _ in sharedState.$currentEpisodeID.stream() {
      guard !Task.isCancelled else { return }
      renderDetails()
    }
  }

  private func observePlayback() async {
    for await _ in sharedState.$playbackStatus.stream() {
      guard !Task.isCancelled else { return }
      renderDetails()
    }
  }

  private func observeOnDeck() async {
    for await _ in sharedState.$onDeck.stream() {
      guard !Task.isCancelled else { return }
      renderDetails()
    }
  }

  private func observeTimeFormat() async {
    for await _ in userSettings.$showTimeRemainingInEpisodeLists.stream() {
      guard !Task.isCancelled else { return }
      renderDetails()
    }
  }

  private func makeHub(_ template: CPListTemplate, reset: Bool) -> CarPlaySmartListHub {
    CarPlaySmartListHub(
      template: template,
      select: { [weak self] id in
        self?.open(id, reset: reset)
      },
      retry: { [weak self] in self?.observeCatalog() }
    )
  }

  private func observeCatalog() {
    catalogTask?.cancel()
    unreadTask?.cancel()
    counts = [:]
    catalog = .loading
    renderCatalog()
    catalogTask = Task { [weak self] in
      guard let self else { return }
      do {
        for try await definitions in observatory.smartLists() {
          try Task.checkCancellation()
          self.definitions = definitions
          catalog = .ready(definitions, counts)
          for detail in details {
            if let definition = definitions.first(where: { $0.id == detail.definition.id }) {
              detail.update(definition)
            } else {
              detail.stop()
              visited.remove(detail.definition.id)
              replacements.append(makeHub(detail.list.template, reset: true))
            }
          }
          let removed = details.filter { detail in
            !definitions.contains { $0.id == detail.definition.id }
          }
          details.removeAll { detail in removed.contains { $0 === detail } }
          renderCatalog()
          for detail in removed { deleted?(detail.list.template) }
        }
      } catch {
        guard !Task.isCancelled else { return }
        Self.log.caughtError("CarPlay Smart List catalog failed", error)
        catalog = .failed
        renderCatalog()
      }
    }
    unreadTask = Task { [weak self] in
      guard let self else { return }
      do {
        for try await counts in observatory.smartListUnreadCounts() {
          try Task.checkCancellation()
          self.counts = counts
          if case .ready = catalog { catalog = .ready(definitions, counts) }
          renderCatalog()
        }
      } catch {
        guard !Task.isCancelled else { return }
        Self.log.caughtError("CarPlay Smart List unread counts unavailable", error)
        counts = [:]
        if case .ready = catalog { catalog = .ready(definitions, [:]) }
        renderCatalog()
      }
    }
  }

  private func renderCatalog() {
    root?.update(catalog, restricted: restricted)
    for hub in replacements { hub.update(catalog, restricted: restricted) }
  }

  private func renderDetails() {
    for detail in details { detail.render() }
  }

  private func open(_ id: SmartList.ID, reset: Bool) {
    guard let selection, canNavigate?() == true,
      let definition = definitions.first(where: { $0.id == id })
    else { return }
    selection.cancel()
    let detail = CarPlaySmartListDetail(definition, selection: selection)
    details.append(detail)
    detail.restricted = restricted
    detail.start()
    navigate?(detail.list.template, reset)
  }

  func canOpen(_ template: CPTemplate) -> Bool {
    details.contains { $0.list.template === template }
  }

  func navigationChanged(templates: [CPTemplate], rootVisible: Bool) {
    for detail in details {
      if templates.contains(where: { $0 === detail.list.template }) {
        visited.insert(detail.definition.id)
        detail.list.setArtworkEnabled(templates.last === detail.list.template)
      } else {
        selection?.cancel()
        detail.stop()
      }
    }
    details.removeAll { detail in !templates.contains { $0 === detail.list.template } }
    for hub in replacements where !templates.contains(where: { $0 === hub.template }) { hub.stop() }
    replacements.removeAll { hub in !templates.contains { $0 === hub.template } }
    guard templates.count == 1, rootVisible, !visited.isEmpty else { return }
    let ids = visited
    visited = []
    Task { [smartListRepo] in
      for id in ids {
        do {
          try await smartListRepo.markSeen(id)
        } catch {
          Self.log.caughtError("CarPlay Smart List mark seen failed: list=\(id)", error)
        }
      }
    }
  }

  func stop() {
    catalogTask?.cancel()
    unreadTask?.cancel()
    stateTask?.cancel()
    catalogTask = nil
    unreadTask = nil
    stateTask = nil
    root?.stop()
    for hub in replacements { hub.stop() }
    for detail in details { detail.stop() }
    root = nil
    replacements = []
    details = []
    visited = []
    selection = nil
    canNavigate = nil
    navigate = nil
    deleted = nil
  }
}
