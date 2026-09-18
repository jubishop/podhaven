// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import Foundation
import Logging

@MainActor
protocol CarPlayInterfaceControlling: AnyObject {
  var delegate: (any CPInterfaceControllerDelegate)? { get set }
  var topTemplate: CPTemplate? { get }
  var templates: [CPTemplate] { get }
  func setRootTemplate(
    _ rootTemplate: CPTemplate,
    animated: Bool,
    completion: ((Bool, (any Error)?) -> Void)?
  )
  func pushTemplate(
    _ templateToPush: CPTemplate,
    animated: Bool,
    completion: ((Bool, (any Error)?) -> Void)?
  )
  func popToRootTemplate(animated: Bool, completion: ((Bool, (any Error)?) -> Void)?)
  func presentTemplate(
    _ templateToPresent: CPTemplate,
    animated: Bool,
    completion: ((Bool, (any Error)?) -> Void)?
  )
  func dismissTemplate(animated: Bool, completion: ((Bool, (any Error)?) -> Void)?)
}

extension CPInterfaceController: CarPlayInterfaceControlling {}

extension Container {
  @MainActor var carPlayCoordinator: Factory<CarPlayCoordinator> {
    Factory(self) { CarPlayCoordinator() }
  }
}

@MainActor
final class CarPlayCoordinator: NSObject, CPNowPlayingTemplateObserver,
  CPSessionConfigurationDelegate, CPInterfaceControllerDelegate, CPTabBarTemplateDelegate
{
  @MainActor private final class Connection {
    enum Navigation { case idle, pushingNowPlaying, returningToQueue, browsingPodcasts }
    let controller: any CarPlayInterfaceControlling
    let selection = Container.shared.carPlaySelection()
    let upNext = Container.shared.carPlayUpNext()
    let podcasts = Container.shared.carPlayPodcasts()
    var root: CPTabBarTemplate?
    var session: (any CarPlaySession)?
    var navigation = Navigation.idle
    var activeRoot: CPTabBarTemplate?
    var selectedTab: CPTemplate?

    init(_ controller: any CarPlayInterfaceControlling) { self.controller = controller }

    func clearHandlers() {
      upNext.stop()
      podcasts.stop()
      selection.disconnect()
      controller.delegate = nil
      root?.delegate = nil
      session?.delegate = nil
      session = nil
      activeRoot = nil
      selectedTab = nil
      navigation = .idle
      guard let root else { return }
      for case let list as CPListTemplate in root.templates {
        for section in list.sections {
          for case let item as CPListItem in section.items { item.handler = nil }
        }
      }
    }
  }

  @DynamicInjected(\.appLauncher) private var appLauncher
  @DynamicInjected(\.carPlayNowPlaying) private var nowPlaying
  private static let log = Log.as("CarPlayCoordinator")
  private var connection: Connection?

  fileprivate override init() { super.init() }

  func connect(_ controller: any CarPlayInterfaceControlling) {
    guard connection?.controller !== controller else { return }
    if let old = connection { disconnect(old.controller) }
    let connection = Connection(controller)
    self.connection = connection
    installRoot(for: connection, state: .ready)
    appLauncher.prepareForBrowsing()
    Self.log.info("CarPlay connected; shared data observers started")
  }

  func disconnect(_ controller: any CarPlayInterfaceControlling) {
    guard let connection, connection.controller === controller else { return }
    connection.clearHandlers()
    nowPlaying.remove(self)
    nowPlaying.updateNowPlayingButtons([])
    nowPlaying.isUpNextButtonEnabled = false
    nowPlaying.isAlbumArtistButtonEnabled = false
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
      guard let self, let connection, self.connection === connection, connection.root === root
      else { return }
      guard success else {
        if let error {
          Self.log.caughtError("CarPlay root presentation failed: state=\(state)", error)
        } else {
          Self.log.error("CarPlay root presentation was rejected: state=\(state)")
        }
        if state == .ready { self.installRoot(for: connection, state: .unavailable) }
        return
      }
      if state == .ready { self.activate(connection, root: root) }
      Self.log.info("CarPlay root presented: state=\(state), tabs=\(root.templates.count)")
    }
  }

  private func activate(_ connection: Connection, root: CPTabBarTemplate) {
    guard connection.activeRoot !== root, let queue = root.templates.first as? CPListTemplate else {
      return
    }
    connection.activeRoot = root
    connection.selectedTab = root.templates.first
    connection.controller.delegate = self
    root.delegate = self
    connection.selection.connect()
    connection.selection.showNowPlaying = { [weak self, weak connection] in
      guard let self, let connection, self.connection === connection else { return }
      self.showNowPlaying(connection)
    }
    connection.selection.showError = { [weak self, weak connection] message in
      guard let self, let connection, self.connection === connection else { return }
      self.showError(message, connection: connection)
    }
    connection.session = Container.shared.carPlaySession()(self)
    connection.upNext.restricted =
      connection.session?.limitedUserInterfaces.contains(.lists) == true
    connection.upNext.start(CarPlayEpisodeList(template: queue, selection: connection.selection))
    if let podcasts = root.templates.last as? CPListTemplate {
      connection.podcasts.canNavigate = { [weak self, weak connection] in
        guard let self, let connection, self.connection === connection else { return false }
        return connection.navigation == .idle
      }
      connection.podcasts.navigate = { [weak self, weak connection] template, reset in
        guard let self, let connection, self.connection === connection else { return }
        self.showPodcastTemplate(template, reset: reset, connection: connection)
      }
      connection.podcasts.showError = connection.selection.showError
      connection.podcasts.restricted = connection.upNext.restricted
      connection.podcasts.start(podcasts, selection: connection.selection)
      updatePodcastNavigation(connection)
    }
    nowPlaying.isAlbumArtistButtonEnabled = false
    nowPlaying.isUpNextButtonEnabled = true
    nowPlaying.upNextTitle = "Up Next"
    nowPlaying.add(self)
    let makeRateButton = Container.shared.carPlayRateButton()
    let button = makeRateButton { [weak self, weak connection] in
      guard let self, let connection, self.connection === connection else { return }
      let rates =
        Container.shared.mpRemoteCommandCenter().changePlaybackRate.supportedPlaybackRates
      let current = Container.shared.sharedState().playRate
      let next = rates.map(\.floatValue).first { $0 > current + 0.01 } ?? rates.first?.floatValue
      guard let next else { return }
      Container.shared.commandCenterStream().continuation.yield(.changePlaybackRate(next))
    }
    nowPlaying.updateNowPlayingButtons([button])
  }

  private func showNowPlaying(_ connection: Connection) {
    guard connection.controller.topTemplate !== CPNowPlayingTemplate.shared,
      connection.navigation == .idle
    else { return }
    guard connection.controller.templates.count < 5 else {
      showError("Return to Up Next and try again.", connection: connection)
      return
    }
    connection.navigation = .pushingNowPlaying
    connection.controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true) {
      [weak self, weak connection] success, error in
      guard let self, let connection, self.connection === connection else { return }
      connection.navigation = .idle
      self.updatePodcastNavigation(connection)
      guard !success else { return }
      if let error {
        Self.log.caughtError("CarPlay Now Playing presentation failed", error)
      } else {
        Self.log.error("CarPlay Now Playing presentation was rejected")
      }
      self.showError("Couldn't open Now Playing. Try again.", connection: connection)
    }
  }

  private func showPodcastTemplate(_ template: CPListTemplate, reset: Bool, connection: Connection)
  {
    guard connection.navigation == .idle else { return }
    connection.navigation = .browsingPodcasts
    let push = { [weak self, weak connection] in
      guard let self, let connection, self.connection === connection else { return }
      guard connection.podcasts.canOpen(template), connection.controller.templates.count < 4 else {
        connection.navigation = .idle
        self.updatePodcastNavigation(connection)
        return
      }
      connection.controller.pushTemplate(template, animated: true) {
        [weak self, weak connection] success, error in
        guard let self, let connection, self.connection === connection else { return }
        connection.navigation = .idle
        self.updatePodcastNavigation(connection)
        if let error {
          Self.log.caughtError("CarPlay podcast navigation failed", error)
        } else if !success {
          Self.log.error("CarPlay podcast navigation was rejected")
        }
        if !success { self.showError("Couldn't open podcasts. Try again.", connection: connection) }
      }
    }
    if reset {
      connection.controller.popToRootTemplate(animated: false) {
        [weak self, weak connection] success, error in
        guard let self, let connection, self.connection === connection else { return }
        if success || connection.controller.topTemplate === connection.root {
          connection.root?.selectTemplate(at: 2)
          connection.selectedTab = connection.root?.templates.last
          push()
        } else {
          connection.navigation = .idle
          self.updatePodcastNavigation(connection)
          if let error {
            Self.log.caughtError("CarPlay current podcast navigation failed", error)
          } else {
            Self.log.error("CarPlay current podcast navigation was rejected")
          }
          self.showError("Couldn't open this podcast. Try again.", connection: connection)
        }
      }
    } else {
      push()
    }
  }

  private func showError(_ message: String, connection: Connection) {
    let dismiss = CPAlertAction(title: "OK", style: .default) { [weak self, weak connection] _ in
      guard let self, let connection, self.connection === connection else { return }
      connection.controller.dismissTemplate(animated: true) { success, error in
        if let error {
          Self.log.caughtError("CarPlay error dismissal failed", error)
        } else if !success {
          Self.log.error("CarPlay error dismissal was rejected")
        }
      }
    }
    connection.controller.presentTemplate(
      CPAlertTemplate(titleVariants: [message], actions: [dismiss]),
      animated: true
    ) { success, error in
      if let error {
        Self.log.caughtError("CarPlay error presentation failed", error)
      } else if !success {
        Self.log.error("CarPlay error presentation was rejected")
      }
    }
  }

  func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
    guard let connection, let root = connection.root, connection.navigation == .idle else { return }
    connection.navigation = .returningToQueue
    connection.controller.popToRootTemplate(animated: true) {
      [weak self, weak connection] success, error in
      guard let self, let connection, self.connection === connection else { return }
      connection.navigation = .idle
      if success || connection.controller.topTemplate === root {
        root.selectTemplate(at: 0)
        connection.selectedTab = root.templates.first
      } else {
        if let error {
          Self.log.caughtError("CarPlay return to queue failed", error)
        } else {
          Self.log.error("CarPlay return to queue was rejected")
        }
        self.showError("Couldn't open Up Next. Try again.", connection: connection)
      }
      self.updatePodcastNavigation(connection)
    }
  }

  func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
    connection?.podcasts.openCurrentPodcast()
  }

  func templateDidAppear(_ aTemplate: CPTemplate, animated: Bool) {
    guard let connection, connection.navigation == .idle,
      connection.controller.templates.contains(where: { $0 === aTemplate })
        || connection.root?.templates.contains(where: { $0 === aTemplate }) == true
    else { return }
    updatePodcastNavigation(connection)
  }

  func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
    guard let connection, connection.root === tabBarTemplate, connection.navigation == .idle else {
      return
    }
    connection.selectedTab = selectedTemplate
    updatePodcastNavigation(connection)
  }

  private func updatePodcastNavigation(_ connection: Connection) {
    connection.podcasts.navigationChanged(
      templates: connection.controller.templates,
      rootVisible: connection.selectedTab === connection.root?.templates.last
    )
  }

  func sessionConfiguration(
    _ sessionConfiguration: CPSessionConfiguration,
    limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface
  ) {
    guard let connection, connection.session === sessionConfiguration else { return }
    connection.upNext.restricted = limitedUserInterfaces.contains(.lists)
    connection.podcasts.restricted = limitedUserInterfaces.contains(.lists)
  }
}
