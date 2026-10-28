// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@MainActor
private final class DisplayFrameWaiter: NSObject {
  private var continuation: CheckedContinuation<Void, Never>?
  private var displayLink: CADisplayLink?
  private var remainingFrameCount = 0

  func wait(forFrameCount frameCount: Int = 1) async {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      remainingFrameCount = frameCount
      let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
      self.displayLink = displayLink
      displayLink.add(to: .main, forMode: .common)
    }
  }

  @objc private func displayLinkDidFire() {
    remainingFrameCount -= 1
    guard remainingFrameCount == 0 else { return }
    displayLink?.invalidate()
    displayLink = nil
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class TranscriptPlaybackState: ObservableObject {
  @Published var currentTime: TimeInterval

  init(currentTime: TimeInterval) {
    self.currentTime = currentTime
  }
}

private struct TranscriptPlaybackTestView: View {
  @ObservedObject var playbackState: TranscriptPlaybackState
  let transcript: Transcript

  var body: some View {
    PlayBarTranscriptView(
      transcript: transcript,
      currentTime: playbackState.currentTime
    )
    .frame(width: 134, height: 500)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

@Suite("of PlayBarSheet tests", .container)
@MainActor struct PlayBarSheetTests {
  private struct PixelBuffer {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]

    func differingByteCount(from other: PixelBuffer) -> Int {
      guard
        width == other.width,
        height == other.height,
        bytesPerRow == other.bytesPerRow
      else { return .max }

      return zip(pixels, other.pixels)
        .reduce(into: 0) { differenceCount, pair in
          if abs(Int(pair.0) - Int(pair.1)) > 1 {
            differenceCount += 1
          }
        }
    }
  }

  private static func withWindow<V: View>(
    _ rootView: V,
    size: CGSize = CGSize(width: 390, height: 844),
    _ body: @MainActor (UIWindow) async throws -> Void
  ) async throws {
    try await withHostedTestWindow(TestHostingController(rootView: rootView), size: size, body)
  }

  private static func render(_ view: UIView) throws -> PixelBuffer {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.preferredRange = .standard
    let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
      .image { _ in
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
      }
    let cgImage = try #require(image.cgImage)
    try #require(cgImage.bitsPerPixel == 32)
    try #require(
      cgImage.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little
        && cgImage.alphaInfo == .premultipliedFirst
    )
    let data = try #require(cgImage.dataProvider?.data)
    let bytes = try #require(CFDataGetBytePtr(data))
    return PixelBuffer(
      width: cgImage.width,
      height: cgImage.height,
      bytesPerRow: cgImage.bytesPerRow,
      pixels: Array(
        UnsafeBufferPointer(
          start: bytes,
          count: CFDataGetLength(data)
        )
      )
    )
  }

  @Test(
    "highlighting stays on one transcript block as word timing advances",
    .enabled(
      if: ProcessInfo.processInfo.isiOSAppOnMac,
      "SwiftUI does not expose hosted rendering in iOS Simulator"
    )
  )
  func transcriptHighlightStaysOnActiveBlock() async throws {
    let transcript = Transcript(
      segments: [
        TranscriptSegment(
          start: 0,
          end: 8,
          text:
            "Stable transcript highlighting should never rearrange nearby words during playback.",
          words: [
            TranscriptWord(start: 0, end: 1, text: "Stable"),
            TranscriptWord(start: 1, end: 2, text: " transcript"),
            TranscriptWord(start: 2, end: 3, text: " highlighting"),
            TranscriptWord(start: 3, end: 4, text: " should"),
            TranscriptWord(start: 4, end: 5, text: " never"),
            TranscriptWord(start: 5, end: 6, text: " rearrange"),
            TranscriptWord(start: 6, end: 6.5, text: " nearby"),
            TranscriptWord(start: 6.5, end: 7, text: " words"),
            TranscriptWord(start: 7, end: 7.5, text: " during"),
            TranscriptWord(start: 7.5, end: 8, text: " playback."),
          ]
        )
      ],
      locale: "en-US",
      createdAt: Date()
    )
    let playbackState = TranscriptPlaybackState(currentTime: -1)
    try await Self.withWindow(
      TranscriptPlaybackTestView(playbackState: playbackState, transcript: transcript),
      size: CGSize(width: 160, height: 520)
    ) { window in
      let displayFrameWaiter = DisplayFrameWaiter()

      await displayFrameWaiter.wait()
      let inactiveRendering = try Self.render(window)
      await displayFrameWaiter.wait()
      let repeatedInactiveRendering = try Self.render(window)

      playbackState.currentTime = 3.5
      await displayFrameWaiter.wait(forFrameCount: 30)
      let activeBlockRendering = try Self.render(window)
      await displayFrameWaiter.wait()
      let repeatedActiveBlockRendering = try Self.render(window)

      playbackState.currentTime = 4.5
      await displayFrameWaiter.wait(forFrameCount: 30)
      let advancedWordRendering = try Self.render(window)
      await displayFrameWaiter.wait()
      let repeatedAdvancedWordRendering = try Self.render(window)
      let stableNoise = max(
        inactiveRendering.differingByteCount(from: repeatedInactiveRendering),
        max(
          activeBlockRendering.differingByteCount(from: repeatedActiveBlockRendering),
          advancedWordRendering.differingByteCount(from: repeatedAdvancedWordRendering)
        )
      )
      let tolerance = stableNoise + 64

      #expect(
        activeBlockRendering.differingByteCount(from: inactiveRendering) > tolerance,
        "The active transcript block did not receive a visible highlight"
      )
      #expect(
        advancedWordRendering.differingByteCount(from: activeBlockRendering) <= tolerance,
        "The highlighted transcript changed while playback remained in the same text block"
      )
    }
  }
}
