// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import ImageIO
import Logging
import PhotosUI
import Sentry
import SwiftUI
import UniformTypeIdentifiers

protocol FeedbackPhotoLoading: Sendable {
  func loadFeedbackPhotoData() async throws -> Data?
}

extension PhotosPickerItem: FeedbackPhotoLoading {
  func loadFeedbackPhotoData() async throws -> Data? {
    try await loadTransferable(type: Data.self)
  }
}

private enum FeedbackPhotoPreparationState: Equatable, Sendable {
  case empty
  case preparing
  case prepared(failedCount: Int)
}

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
  private var photoPreparationState = FeedbackPhotoPreparationState.empty

  nonisolated private static let log = Log.as(LogSubsystem.SettingsView.feedback)
  nonisolated static let maximumPhotoCount = 5
  nonisolated private static let maximumTotalPhotoBytes = 8_000_000

  var isPreparingPhotos: Bool {
    photoPreparationState == .preparing
  }

  var photoPreparationFailureCount: Int {
    guard case .prepared(let failedCount) = photoPreparationState else { return 0 }
    return failedCount
  }

  var canSend: Bool {
    !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isPreparingPhotos
  }

  func selectedPhotosChanged<Photo: FeedbackPhotoLoading>(_ newItems: [Photo]) {
    photoLoadingTask?.cancel()
    let items = Array(newItems.prefix(Self.maximumPhotoCount))
    guard !items.isEmpty else {
      photoLoadingTask = nil
      photoData.new([])
      photoPreparationState = .empty
      return
    }

    photoPreparationState = .preparing
    photoLoadingTask = Task { [weak self, items] in
      guard let self else { return }
      var preparedPhotos: [Data] = []
      var failedCount = 0
      var remainingPhotoBytes = Self.maximumTotalPhotoBytes
      for (index, item) in items.enumerated() {
        guard !Task.isCancelled else { return }
        do {
          guard let sourceData = try await item.loadFeedbackPhotoData() else {
            Self.log.error("Selected photo did not provide image data")
            failedCount += 1
            continue
          }
          guard !Task.isCancelled else { return }
          let remainingPhotoCount = items.count - index
          let maximumByteCount = remainingPhotoBytes / remainingPhotoCount
          let preparedData = await Self.preparePhotoData(
            sourceData,
            maximumByteCount: maximumByteCount
          )
          guard !Task.isCancelled else { return }
          guard let preparedData else {
            Self.log.error(
              "Failed to prepare selected photo within \(maximumByteCount) byte budget"
            )
            failedCount += 1
            continue
          }
          preparedPhotos.append(preparedData)
          remainingPhotoBytes -= preparedData.count
        } catch {
          guard !Task.isCancelled else { return }
          Self.log.caughtError("Failed to load selected photo", error)
          failedCount += 1
        }
      }
      guard !Task.isCancelled else { return }
      self.photoData.new(preparedPhotos)
      self.photoPreparationState = .prepared(failedCount: failedCount)
      self.photoLoadingTask = nil
    }
  }

  func removePhotos() {
    photoLoadingTask?.cancel()
    photoLoadingTask = nil
    photoData.new([])
    photoPreparationState = .empty
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

  @concurrent private static func preparePhotoData(
    _ data: Data,
    maximumByteCount: Int
  ) async -> Data? {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary
      )
    else {
      return nil
    }

    let encodingCandidates = [
      (maximumPixelDimension: 3072, compressionQuality: 0.9),
      (maximumPixelDimension: 2560, compressionQuality: 0.82),
      (maximumPixelDimension: 2048, compressionQuality: 0.75),
      (maximumPixelDimension: 1600, compressionQuality: 0.68),
      (maximumPixelDimension: 1280, compressionQuality: 0.6),
      (maximumPixelDimension: 1024, compressionQuality: 0.5),
    ]
    for candidate in encodingCandidates {
      guard !Task.isCancelled else { return nil }
      guard
        let image = CGImageSourceCreateThumbnailAtIndex(
          source,
          0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: candidate.maximumPixelDimension,
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
        [
          kCGImageDestinationLossyCompressionQuality: candidate.compressionQuality
        ] as CFDictionary
      )
      guard CGImageDestinationFinalize(destination) else { return nil }
      let preparedData = output as Data
      if preparedData.count <= maximumByteCount { return preparedData }
    }
    return nil
  }
}
