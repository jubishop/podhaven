// Copyright Justin Bishop, 2026

import CarPlay

@testable import PodHaven

@MainActor
final class FakeCarPlayInterfaceController: CarPlayInterfaceControlling {
  weak var delegate: (any CPInterfaceControllerDelegate)?
  private(set) var roots: [CPTemplate] = []
  private(set) var completions: [(Bool, (any Error)?) -> Void] = []
  private(set) var pushed: [CPTemplate] = []
  private(set) var alerts: [CPTemplate] = []
  var templates: [CPTemplate] = []
  var topTemplate: CPTemplate? { templates.last }
  var pushResult = true
  var popResult = true

  func setRootTemplate(
    _ rootTemplate: CPTemplate,
    animated: Bool,
    completion: ((Bool, (any Error)?) -> Void)?
  ) {
    roots.append(rootTemplate)
    templates = [rootTemplate]
    if let completion { completions.append(completion) }
  }

  func pushTemplate(
    _ templateToPush: CPTemplate,
    animated: Bool,
    completion: ((Bool, (any Error)?) -> Void)?
  ) {
    pushed.append(templateToPush)
    if pushResult {
      templates.append(templateToPush)
      delegate?.templateDidAppear?(templateToPush, animated: animated)
    }
    completion?(pushResult, nil)
  }

  func popToRootTemplate(animated: Bool, completion: ((Bool, (any Error)?) -> Void)?) {
    if popResult {
      templates = Array(templates.prefix(1))
      if let topTemplate { delegate?.templateDidAppear?(topTemplate, animated: animated) }
    }
    completion?(popResult, nil)
  }

  func goBack() {
    guard templates.count > 1 else { return }
    templates.removeLast()
    if let topTemplate { delegate?.templateDidAppear?(topTemplate, animated: true) }
  }

  func presentTemplate(
    _ templateToPresent: CPTemplate,
    animated: Bool,
    completion: ((Bool, (any Error)?) -> Void)?
  ) {
    alerts.append(templateToPresent)
    completion?(true, nil)
  }

  func dismissTemplate(animated: Bool, completion: ((Bool, (any Error)?) -> Void)?) {
    completion?(true, nil)
  }
}

@MainActor
final class FakeCarPlayNowPlaying: CarPlayNowPlaying {
  var isUpNextButtonEnabled = false
  var isAlbumArtistButtonEnabled = false
  var upNextTitle = ""
  var buttons: [CPNowPlayingButton] = []
  var observers: [any CPNowPlayingTemplateObserver] = []
  func add(_ observer: any CPNowPlayingTemplateObserver) { observers.append(observer) }
  func remove(_ observer: any CPNowPlayingTemplateObserver) {
    observers.removeAll { $0 === observer }
  }
  func updateNowPlayingButtons(_ buttons: [CPNowPlayingButton]) { self.buttons = buttons }
}

@MainActor
final class FakeCarPlaySession: CarPlaySession {
  var limitedUserInterfaces: CPLimitableUserInterface = []
  weak var delegate: (any CPSessionConfigurationDelegate)?
}
