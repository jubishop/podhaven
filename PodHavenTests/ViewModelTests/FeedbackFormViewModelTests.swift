// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import PodHaven

@Suite("of FeedbackFormViewModel tests", .container)
@MainActor final class FeedbackFormViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fakeSentryFeedbackCapture) private var fakeSentryFeedbackCapture

  @Test("sendFeedback sends report, multiple photos, and confirmation")
  func sendFeedbackSendsReportAndPresentsConfirmationAlert() throws {
    let viewModel = FeedbackFormViewModel()
    let firstPhotoData = try #require(Self.photoData(color: .red))
    let secondPhotoData = try #require(Self.photoData(color: .blue))
    viewModel.message = "Please add folders."
    viewModel.name = "Justin"
    viewModel.email = "justin@example.com"
    viewModel.photoData.new([firstPhotoData, secondPhotoData])

    viewModel.sendFeedback()

    #expect(fakeSentryFeedbackCapture.feedbacks.count == 1)
    let feedback = try #require(fakeSentryFeedbackCapture.feedbacks.first)
    #expect(feedback.message == "Please add folders.")
    #expect(feedback.name == "Justin")
    #expect(feedback.email == "justin@example.com")
    #expect(feedback.source == "custom")

    let attachments = feedback.attachments
    #expect(
      attachments.map(\.filename) == [
        "log.ndjson",
        "widget-log.ndjson",
        "screenshot.jpg",
        "screenshot-2.jpg",
      ]
    )
    #expect(attachments[0].path == AppInfo.logFileURL.path)
    #expect(attachments[1].path == WidgetInfo.logFileURL.path)
    #expect(attachments[2].contentType == "image/jpeg")
    #expect(attachments[2].data == firstPhotoData)
    #expect(attachments[3].contentType == "image/jpeg")
    #expect(attachments[3].data == secondPhotoData)
    #expect(alert.config?.title == "Feedback Sent")
  }

  @Test("photo preparation reports selected items that fail to load")
  func photoPreparationReportsSelectedItemsThatFailToLoad() async throws {
    let viewModel = FeedbackFormViewModel()
    let photoData = try #require(Self.photoData(color: .red))

    viewModel.selectedPhotosChanged([
      FakeFeedbackPhoto(outcome: .failure),
      FakeFeedbackPhoto(outcome: .data(photoData)),
    ])

    try await Wait.until(
      { @MainActor in !viewModel.isPreparingPhotos },
      { @MainActor in "Photo preparation did not finish" }
    )

    #expect(viewModel.photoData.value.count == 1)
    #expect(viewModel.photoPreparationFailureCount == 1)
  }

  @Test("photo preparation bounds the total encoded attachment payload")
  func photoPreparationBoundsTotalEncodedAttachmentPayload() async throws {
    let viewModel = FeedbackFormViewModel()
    let sourceData = try Self.highEntropyPhotoData()

    viewModel.selectedPhotosChanged(
      Array(
        repeating: FakeFeedbackPhoto(outcome: .data(sourceData)),
        count: FeedbackFormViewModel.maximumPhotoCount
      )
    )

    try await Wait.until(
      { @MainActor in !viewModel.isPreparingPhotos },
      { @MainActor in "Photo preparation did not finish" }
    )

    let photos = viewModel.photoData.value
    #expect(photos.count == FeedbackFormViewModel.maximumPhotoCount)
    #expect(photos.reduce(0) { $0 + $1.count } <= 8_000_000)
  }

  private static func photoData(color: UIColor) -> Data? {
    UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
      .image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
      }
      .jpegData(compressionQuality: 0.9)
  }

  private static func highEntropyPhotoData() throws -> Data {
    let dimension = 2048
    let bytesPerRow = dimension * 3
    var bytes = Data(count: bytesPerRow * dimension)
    bytes.withUnsafeMutableBytes { rawBuffer in
      guard let buffer = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
      var state: UInt64 = 0x4D59_5DF4_D0F3_3173
      for index in 0..<rawBuffer.count {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        buffer[index] = UInt8(truncatingIfNeeded: state >> 24)
      }
    }

    let provider = try #require(CGDataProvider(data: bytes as CFData))
    let image = try #require(
      CGImage(
        width: dimension,
        height: dimension,
        bitsPerComponent: 8,
        bitsPerPixel: 24,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
      )
    )
    let output = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    )
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
    )
    try #require(CGImageDestinationFinalize(destination))
    return output as Data
  }
}

private struct FakeFeedbackPhoto: FeedbackPhotoLoading {
  enum Outcome: Sendable {
    case data(Data?)
    case failure
  }

  let outcome: Outcome

  func loadFeedbackPhotoData() async throws -> Data? {
    switch outcome {
    case .data(let data):
      data
    case .failure:
      throw FakeFeedbackPhotoError.loadFailed
    }
  }
}

private enum FakeFeedbackPhotoError: Error {
  case loadFailed
}
