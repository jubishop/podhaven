// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import Logging

@MainActor
protocol CarPlayInterfaceControlling: AnyObject {
  func setRootTemplate(
    _ rootTemplate: CPTemplate,
    animated: Bool,
    completion: ((Bool, (any Error)?) -> Void)?
  )
}

extension CPInterfaceController: CarPlayInterfaceControlling {}

extension Container {
  @MainActor var carPlayCoordinator: Factory<CarPlayCoordinator> {
    Factory(self) { CarPlayCoordinator() }
  }
}

@MainActor
final class CarPlayCoordinator {
  @MainActor private final class Connection {
    let controller: any CarPlayInterfaceControlling
    var root: CPTabBarTemplate?

    init(_ controller: any CarPlayInterfaceControlling) {
      self.controller = controller
    }

    func clearHandlers() {
      guard let root else { return }
      for case let list as CPListTemplate in root.templates {
        for section in list.sections {
          for case let item as CPListItem in section.items {
            item.handler = nil
          }
        }
      }
    }
  }

  @DynamicInjected(\.appLauncher) private var appLauncher

  private static let log = Log.as("CarPlayCoordinator")
  private var connection: Connection?

  fileprivate init() {}

  func connect(_ controller: any CarPlayInterfaceControlling) {
    guard connection?.controller !== controller else { return }
    connection?.clearHandlers()
    let connection = Connection(controller)
    self.connection = connection
    installRoot(for: connection, state: .ready)
    appLauncher.prepareForBrowsing()
    Self.log.info("CarPlay connected; shared data observers started")
  }

  func disconnect(_ controller: any CarPlayInterfaceControlling) {
    guard let connection, connection.controller === controller else { return }
    connection.clearHandlers()
    self.connection = nil
    Self.log.info("CarPlay disconnected; released presentation")
  }

  private func installRoot(for connection: Connection, state: CarPlayRootTemplate.State) {
    guard self.connection === connection else { return }
    connection.clearHandlers()
    let root = CarPlayRootTemplate.make(state: state) { [weak self, weak connection] in
      guard let self, let connection, self.connection === connection else { return }
      self.installRoot(for: connection, state: .ready)
    }
    connection.root = root
    connection.controller.setRootTemplate(root, animated: false) {
      [weak self, weak connection] success, error in
      guard let self, let connection, self.connection === connection,
        connection.root === root
      else { return }
      guard success else {
        if let error {
          Self.log.caughtError("CarPlay root presentation failed: state=\(state)", error)
        } else {
          Self.log.error("CarPlay root presentation was rejected: state=\(state)")
        }
        if state == .ready {
          self.installRoot(for: connection, state: .unavailable)
        }
        return
      }
      Self.log.info("CarPlay root presented: state=\(state), tabs=\(root.templates.count)")
    }
  }
}
