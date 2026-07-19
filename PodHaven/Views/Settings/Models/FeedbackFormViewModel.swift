// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import ImageIO
import Logging
import PhotosUI
import Sentry
import SwiftUI
import UniformTypeIdentifiers

extension Container {
  var captureSentryFeedback: Factory<(SentryFeedback) -> Void> {
    Factory(self) {
      { feedback in
        SentrySDK.capture(feedback: feedback)
      }
    }
    .scope(.cached)
  }
}

@Observable @MainActor class FeedbackFormViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.captureSentryFeedback) private var captureSentryFeedback
  @ObservationIgnored private var photoLoadingTask: Task<Void, Never>?

  var message = ""
  var name = ""
  var email = ""
  let photoData = Broadcast<[Data]>([])
  var isPreparingPhotos = false

  nonisolated private static let log = Log.as(LogSubsystem.SettingsView.feedback)
  nonisolated static let maximumPhotoCount = 5
  nonisolated private static let maximumPhotoPixelDimension = 3072
  nonisolated private static let photoCompressionQuality = 0.9

  var canSend: Bool {
    !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isPreparingPhotos
  }

  func selectedPhotosChanged(_ newItems: [PhotosPickerItem]) {
    photoLoadingTask?.cancel()
    let items = Array(newItems.prefix(Self.maximumPhotoCount))
    guard !items.isEmpty else {
      photoData.new([])
      isPreparingPhotos = false
      return
    }

    isPreparingPhotos = true
    photoLoadingTask = Task { [weak self, items] in
      guard let self else { return }
      var preparedPhotos: [Data] = []
      for item in items {
        guard !Task.isCancelled else { return }
        do {
          guard let sourceData = try await item.loadTransferable(type: Data.self) else {
            Self.log.error("Selected photo did not provide image data")
            continue
          }
          guard let preparedData = await Self.preparePhotoData(sourceData) else {
            Self.log.error("Failed to prepare selected photo")
            continue
          }
          preparedPhotos.append(preparedData)
        } catch {
          guard !Task.isCancelled else { return }
          Self.log.caughtError("Failed to load selected photo", error)
        }
      }
      guard !Task.isCancelled else { return }
      self.photoData.new(preparedPhotos)
      self.isPreparingPhotos = false
    }
  }

  func removePhotos() {
    photoLoadingTask?.cancel()
    photoData.new([])
    isPreparingPhotos = false
  }

  func sendFeedback() {
    var attachments: [Attachment] = [
      Attachment(path: AppInfo.logFileURL.path, filename: "log.ndjson"),
      Attachment(path: WidgetInfo.logFileURL.path, filename: "widget-log.ndjson"),
    ]

    for (index, data) in photoData.value.prefix(Self.maximumPhotoCount).enumerated() {
      let filename = index == 0 ? "screenshot.jpg" : "screenshot-\(index + 1).jpg"
      attachments.append(
        Attachment(data: data, filename: filename, contentType: "image/jpeg")
      )
    }

    captureSentryFeedback(
      SentryFeedback(
        message: message,
        name: name.isEmpty ? nil : name,
        email: email.isEmpty ? nil : email,
        source: .custom,
        attachments: attachments
      )
    )
    alert(title: "Feedback Sent", "Thanks for sending feedback.")
  }

  @concurrent private static func preparePhotoData(_ data: Data) async -> Data? {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true,
          kCGImageSourceThumbnailMaxPixelSize: maximumPhotoPixelDimension,
        ] as CFDictionary
      )
    else {
      return nil
    }

    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      return nil
    }
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImageDestinationLossyCompressionQuality: photoCompressionQuality] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}
