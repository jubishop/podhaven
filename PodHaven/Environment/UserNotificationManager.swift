// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Nuke
import SwiftUI
import UIKit
import UserNotifications

extension Container {
  var userNotificationCenter: Factory<any NotifyingCenter> {
    Factory(self) { UNUserNotificationCenter.current() }.scope(.cached)
  }

  var userNotificationManager: Factory<UserNotificationManager> {
    Factory(self) { UserNotificationManager() }.scope(.cached)
  }
}

@Observable
final class UserNotificationManager {
  @ObservationIgnored @DynamicInjected(\.imagePipeline) private var imagePipeline
  @ObservationIgnored private var fileManager: any FileManaging { Container.shared.fileManager() }
  @ObservationIgnored private var notificationCenter: any NotifyingCenter {
    Container.shared.userNotificationCenter()
  }

  private static let log = Log.as("UserNotificationManager")

  // MARK: - State

  private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

  var isAuthorized: Bool {
    switch authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .notDetermined, .denied:
      return false
    @unknown default:
      return false
    }
  }

  var isDenied: Bool {
    authorizationStatus == .denied
  }

  var isNotDetermined: Bool {
    authorizationStatus == .notDetermined
  }

  // MARK: - Initialization

  fileprivate init() {}

  func initialize() async {
    await refreshAuthorizationStatus()
  }

  // MARK: - Public Methods

  func handleScenePhaseChange(to scenePhase: ScenePhase) async {
    guard scenePhase == .active else { return }

    await refreshAuthorizationStatus()
  }

  // Refreshes the current authorization status from the system.
  func refreshAuthorizationStatus() async {
    authorizationStatus = await notificationCenter.authorizationStatus()
    Self.log.debug("Authorization status: \(String(describing: authorizationStatus))")
  }

  // Requests notification authorization if not yet determined.
  // Returns `true` if authorized (either already or newly granted).
  @discardableResult
  func requestAuthorizationIfNeeded() async -> Bool {
    await refreshAuthorizationStatus()

    switch authorizationStatus {
    case .notDetermined:
      return await requestAuthorization()

    case .authorized, .provisional, .ephemeral:
      return true

    case .denied:
      return false

    @unknown default:
      return false
    }
  }

  // Schedules a local notification for new podcast episodes.
  func scheduleNewEpisodeNotification(
    podcast: Podcast,
    episodes: [Episode]
  ) async {
    guard !episodes.isEmpty else {
      Self.log.debug("Skipping notification: no episodes")
      return
    }

    await refreshAuthorizationStatus()
    guard isAuthorized else {
      Self.log.notice("Skipping notification: not authorized")
      return
    }

    let content = UNMutableNotificationContent()
    content.sound = .default

    // Determine image URL: episode image for single episode, podcast image for multiple
    let imageURL: URL
    if episodes.count == 1, let episode = episodes.first {
      content.title = podcast.title
      content.body = episode.title
      imageURL = episode.image ?? podcast.image
    } else {
      content.title = podcast.title
      content.body = "\(episodes.count) new episodes available"
      imageURL = podcast.image
    }

    // Attach image if available
    if let attachment = await createImageAttachment(from: imageURL) {
      content.attachments = [attachment]
    }

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )

    do {
      try await notificationCenter.add(request)
      Self.log.debug(
        """
        Scheduled notification for \(podcast.title):
          \(episodes.map(\.title).joined(separator: "\n  "))
        """
      )
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Private Methods

  private func createImageAttachment(from imageURL: URL) async -> UNNotificationAttachment? {
    do {
      // Load image via Nuke (leverages existing cache)
      let image = try await imagePipeline.image(for: imageURL)

      // Convert to JPEG data
      guard let data = image.jpegData(compressionQuality: 0.8) else {
        Self.log.warning("Failed to convert notification image to JPEG: \(imageURL)")
        return nil
      }

      // Write to temporary file (UNNotificationAttachment requires file URL)
      let tempFile = fileManager.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + ".jpg"
      )
      try await fileManager.writeData(data, to: tempFile)

      // Create attachment
      let attachment = try UNNotificationAttachment(
        identifier: UUID().uuidString,
        url: tempFile,
        options: nil
      )

      return attachment
    } catch {
      Self.log.error(error)
      return nil
    }
  }

  private func requestAuthorization() async -> Bool {
    Self.log.debug("Requesting notification authorization")

    do {
      let granted = try await notificationCenter.requestAuthorization(
        options: [.alert, .sound, .badge]
      )

      await refreshAuthorizationStatus()

      Self.log.debug("Authorization \(granted ? "granted" : "denied")")
      return granted
    } catch {
      Self.log.error(error)
      return false
    }
  }
}
