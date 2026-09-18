// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import Tagged

@MainActor
final class CarPlaySmartListHub {
  enum Content {
    case loading, failed
    case ready([SmartList], [SmartList.ID: Int])
  }

  @DynamicInjected(\.carPlayListLimits) private var limits
  let template: CPListTemplate
  private var content = Content.loading
  private var page = 0
  private var restricted = false
  private var rows: [SmartList.ID: CPListItem] = [:]
  private var controls: [CPListItem] = []
  private let select: (SmartList.ID) -> Void
  private let retry: () -> Void

  init(
    template: CPListTemplate,
    select: @escaping (SmartList.ID) -> Void,
    retry: @escaping () -> Void
  ) {
    self.template = template
    self.select = select
    self.retry = retry
  }

  func update(_ content: Content, restricted: Bool) {
    self.content = content
    self.restricted = restricted
    render()
  }

  private func render() {
    for item in controls { item.handler = nil }
    controls = []
    let entries: [SmartList]
    let counts: [SmartList.ID: Int]
    template.showsSpinnerWhileEmpty = false
    switch content {
    case .loading:
      entries = []
      counts = [:]
      template.showsSpinnerWhileEmpty = true
      template.emptyViewTitleVariants = ["Loading Smart Lists…"]
      template.emptyViewSubtitleVariants = ["Reading saved lists."]
    case .failed:
      entries = []
      counts = [:]
      template.emptyViewTitleVariants = ["Couldn't load Smart Lists"]
      template.emptyViewSubtitleVariants = ["Try again when available."]
      let row = CPListItem(text: "Retry", detailText: "Couldn't load Smart Lists.")
      row.handler = { [weak self] _, completion in
        completion()
        self?.retry()
      }
      controls = [row]
    case .ready(let lists, let unread):
      entries = lists
      counts = unread
      template.emptyViewTitleVariants = ["No Smart Lists"]
      template.emptyViewSubtitleVariants = ["Your saved Smart Lists appear here."]
    }
    let limits = limits()
    let slice = CarPlayPage(
      count: entries.count,
      page: page,
      limits: limits,
      restricted: restricted,
      leading: controls.count
    )
    page = slice.index
    let visible = entries[slice.range]
    let ids = Set(visible.map(\.id))
    for (id, row) in rows where !ids.contains(id) { row.handler = nil }
    rows = rows.filter { ids.contains($0.key) }
    var items = Array(controls.prefix(slice.leadingCount))
    for list in visible {
      let row = rows[list.id] ?? CPListItem(text: list.title, detailText: nil)
      rows[list.id] = row
      row.userInfo = list.id
      row.setText(list.title)
      var detail = ""
      if list.showUnreadBadge, let count = counts[list.id] { detail = "\(count) unread" }
      if slice.limited, list.id == visible.last?.id {
        if !detail.isEmpty { detail += " · " }
        detail += "More Smart Lists available when vehicle limits permit."
      }
      row.setDetailText(detail.isEmpty ? nil : detail)
      row.setImage(UIImage(named: "LucideIcons/\(list.icon.rawValue)"))
      row.accessoryType = .disclosureIndicator
      row.handler = { [weak self, weak row] _, completion in
        completion()
        guard let self, let row, self.rows[list.id] === row else { return }
        self.select(list.id)
      }
      items.append(row)
    }
    for (title, target) in slice.controls {
      let row = CPListItem(text: title, detailText: "Page \(target + 1) of \(slice.last + 1)")
      row.handler = { [weak self, weak row] _, completion in
        completion()
        guard let self, let row, self.controls.contains(where: { $0 === row }) else { return }
        self.page = target
        self.render()
      }
      controls.append(row)
      items.append(row)
    }
    if slice.limited && items.isEmpty {
      template.showsSpinnerWhileEmpty = false
      template.emptyViewTitleVariants = ["List unavailable"]
      template.emptyViewSubtitleVariants = ["Content is limited by the vehicle."]
    }
    template.updateSections(items.isEmpty ? [] : [CPListSection(items: items)])
  }

  func stop() {
    for row in rows.values { row.handler = nil }
    for row in controls { row.handler = nil }
    rows = [:]
    controls = []
  }
}
