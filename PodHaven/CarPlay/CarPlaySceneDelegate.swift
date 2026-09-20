// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private let coordinator = Container.shared.carPlayCoordinator()

  func sceneDidBecomeActive(_ scene: UIScene) {
    coordinator.refreshAssistant()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    coordinator.connect(interfaceController)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    coordinator.disconnect(interfaceController)
  }
}
