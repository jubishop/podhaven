// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

private let supportsHostedAccessibilityInspection = ProcessInfo.processInfo.isiOSAppOnMac

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

    func luminance(atX x: Int, y: Int) -> Double? {
      guard x >= 0, x < width, y >= 0, y < height else { return nil }
      let offset = y * bytesPerRow + x * 4
      let red = Double(pixels[offset + 2]) / 255
      let green = Double(pixels[offset + 1]) / 255
      let blue = Double(pixels[offset]) / 255
      return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
  }

  private static func makeWindow<V: View>(
    _ rootView: V,
    size: CGSize = CGSize(width: 390, height: 844)
  ) throws -> UIWindow {
    let host = UIHostingController(rootView: rootView)
    let scene = try #require(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    )
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: size)
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return window
  }

  private static func accessibilityElements(in root: NSObject) -> [NSObject] {
    var visited: Set<ObjectIdentifier> = []

    func collect(from object: NSObject) -> [NSObject] {
      guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }

      var result = object.isAccessibilityElement ? [object] : []
      if let view = object as? UIView {
        result.append(contentsOf: view.subviews.flatMap { collect(from: $0) })
      }

      let count = object.accessibilityElementCount()
      if count != NSNotFound, count > 0 {
        for index in 0..<count {
          if let child = object.accessibilityElement(at: index) as? NSObject {
            result.append(contentsOf: collect(from: child))
          }
        }
      }

      return result
    }

    return collect(from: root)
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

  private static func progressGlassContrast(
    for element: NSObject,
    in window: UIWindow
  ) throws -> Double {
    let frame = window.convert(
      element.accessibilityFrame,
      from: window.screen.coordinateSpace
    )
    let rendering = try render(window)
    let centerY = Int(frame.midY.rounded())
    let glassSamples = (-3...3)
      .compactMap { offset in
        rendering.luminance(
          atX: Int((frame.minX - 6).rounded()),
          y: centerY + offset
        )
      }
    let artworkSamples = (-3...3)
      .compactMap { offset in
        rendering.luminance(
          atX: Int((frame.minX - 18).rounded()),
          y: centerY + offset
        )
      }
    try #require(!glassSamples.isEmpty && !artworkSamples.isEmpty)
    let glassLuminance = glassSamples.reduce(0, +) / Double(glassSamples.count)
    let artworkLuminance = artworkSamples.reduce(0, +) / Double(artworkSamples.count)
    return abs(glassLuminance - artworkLuminance)
  }

  @Test(
    "highlighting a transcript block preserves the segment layout",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func transcriptHighlightPreservesSegmentLayout() async throws {
    let transcriptText =
      "Stable transcript highlighting should never rearrange nearby words during playback."
    let transcript = Transcript(
      segments: [
        TranscriptSegment(
          start: 0,
          end: 8,
          text: transcriptText,
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

    let width: CGFloat = 134
    func transcriptView(at currentTime: TimeInterval) -> AnyView {
      AnyView(
        PlayBarTranscriptView(transcript: transcript, currentTime: currentTime)
          .frame(width: width, height: 500)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .transaction { transaction in
            transaction.disablesAnimations = true
          }
      )
    }

    let window = try Self.makeWindow(transcriptView(at: -1))
    defer { window.isHidden = true }

    func segmentHeight(expectedValue: String? = nil) async throws -> CGFloat {
      try await Wait.until(
        maxAttempts: 100,
        { @MainActor in
          window.rootViewController?.view.setNeedsLayout()
          window.rootViewController?.view.layoutIfNeeded()
          guard
            let segment = Self.accessibilityElements(in: window)
              .first(where: { $0.accessibilityLabel == transcriptText })
          else { return false }
          guard let expectedValue else { return true }
          return segment.accessibilityValue == expectedValue
        },
        { "Transcript segment never became accessible" }
      )
      let segment = try #require(
        Self.accessibilityElements(in: window)
          .first { $0.accessibilityLabel == transcriptText }
      )
      return segment.accessibilityFrame.height
    }

    let inactiveHeight = try await segmentHeight()
    let host = try #require(window.rootViewController as? UIHostingController<AnyView>)
    host.rootView = transcriptView(at: 3.5)
    let highlightedHeight = try await segmentHeight(expectedValue: "Current text block")

    #expect(
      highlightedHeight == inactiveHeight,
      "Highlighting changed the segment from \(inactiveHeight) to \(highlightedHeight) points"
    )
  }

  @Test(
    "highlighting stays on one transcript block as word timing advances",
    .enabled(
      if: supportsHostedAccessibilityInspection,
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
    let window = try Self.makeWindow(
      TranscriptPlaybackTestView(playbackState: playbackState, transcript: transcript),
      size: CGSize(width: 160, height: 520)
    )
    defer { window.isHidden = true }
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

  @Test(
    "controls remain distinct from bright artwork at both detents",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func controlsRemainDistinctFromBrightArtworkAtBothDetents() async throws {
    let transcript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 4, text: "Follow along")],
      locale: "en-US",
      createdAt: Date()
    )
    let episode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Stable Transcript Controls")
    )
    try await Container.shared.repo()
      .updateTranscript(episode.id, transcript: transcript.jsonString())
    let transcribedEpisode = try #require(
      try await Container.shared.repo().podcastEpisode(episode.id)
    )
    var onDeck = OnDeck(from: transcribedEpisode)
    onDeck.artwork = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
      .image { context in
        UIColor(red: 0.72, green: 0.75, blue: 0, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
      }
    Container.shared.sharedState().$onDeck.new(onDeck)

    let viewModel = PlayBarViewModel()
    let transcriptObservationTask = Task {
      await viewModel.observeTranscript()
    }
    defer { transcriptObservationTask.cancel() }
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in viewModel.canExpandTranscript },
      { @MainActor in "Transcribed play bar never loaded its transcript" }
    )

    let window = try Self.makeWindow(
      PlayBarSheet(viewModel: viewModel)
        .preferredColorScheme(.dark)
    )
    defer { window.isHidden = true }

    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return Self.accessibilityElements(in: window)
          .contains { $0.accessibilityLabel == "Show Transcript" }
      },
      { @MainActor in
        let labels = Self.accessibilityElements(in: window)
          .compactMap(\.accessibilityLabel)
        return "Play bar never exposed the Show Transcript action; labels: \(labels)"
      }
    )
    let showTranscriptButton = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel == "Show Transcript" }
    )
    let mediumPlaybackPosition = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel == "Playback Position" }
    )
    let mediumContrast = try Self.progressGlassContrast(
      for: mediumPlaybackPosition,
      in: window
    )

    #expect(
      mediumContrast >= 0.1,
      "Medium glass differed from the surrounding artwork by only \(mediumContrast) luminance"
    )

    #expect(showTranscriptButton.accessibilityActivate())

    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return Self.accessibilityElements(in: window)
          .contains { $0.accessibilityLabel == "Collapse Transcript" }
      },
      { "Play bar never expanded its transcript" }
    )
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        guard
          let playbackPosition = Self.accessibilityElements(in: window)
            .first(where: { $0.accessibilityLabel == "Playback Position" })
        else { return false }
        return try Self.progressGlassContrast(
          for: playbackPosition,
          in: window
        ) >= 0.1
      },
      { "Expanded glass never finished applying its contrast treatment" }
    )
    let expandedPlaybackPosition = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel == "Playback Position" }
    )
    let expandedContrast = try Self.progressGlassContrast(
      for: expandedPlaybackPosition,
      in: window
    )

    #expect(
      expandedContrast >= 0.1,
      "Expanded glass differed from the surrounding artwork by only \(expandedContrast) luminance"
    )
  }

  @Test("transcribed episodes expand to a synchronized full-height transcript")
  func transcribedEpisodeOffersFullHeightDetent() async throws {
    let episode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Expandable Transcript")
    )
    let transcript = Transcript(
      segments: [
        TranscriptSegment(
          start: 0,
          end: 4,
          text: "Follow along",
          words: [
            TranscriptWord(start: 0, end: 2, text: "Follow"),
            TranscriptWord(start: 2, end: 4, text: " along"),
          ]
        )
      ],
      locale: "en-US",
      createdAt: Date()
    )
    try await Container.shared.repo()
      .updateTranscript(
        episode.id,
        transcript: transcript.jsonString()
      )
    let transcribedEpisode = try #require(
      try await Container.shared.repo().podcastEpisode(episode.id)
    )
    Container.shared.stateManager().setOnDeck(transcribedEpisode)
    Container.shared.stateManager().setCurrentTime(.seconds(3))

    let viewModel = PlayBarViewModel()
    let transcriptObservationTask = Task {
      await viewModel.observeTranscript()
    }
    defer { transcriptObservationTask.cancel() }
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in viewModel.canExpandTranscript },
      { @MainActor in "Transcribed play bar never loaded its transcript" }
    )

    let window = try Self.makeWindow(PlayBarSheet(viewModel: viewModel))
    defer {
      window.isHidden = true
    }

    guard supportsHostedAccessibilityInspection else { return }
    let presentedView = try #require(window.rootViewController?.view)
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in
        Self.accessibilityElements(in: presentedView)
          .contains { $0.accessibilityLabel == "Show Transcript" }
      },
      { "Play bar never exposed the Show Transcript action" }
    )
    let showTranscriptButton = try #require(
      Self.accessibilityElements(in: presentedView)
        .first { $0.accessibilityLabel == "Show Transcript" }
    )
    #expect(showTranscriptButton.accessibilityActivate())
    try await Wait.until(
      maxAttempts: 400,
      { @MainActor in
        presentedView.setNeedsLayout()
        presentedView.layoutIfNeeded()
        return Self.accessibilityElements(in: presentedView)
          .contains { $0.accessibilityLabel == "Follow along" }
      },
      { "Expanded play bar never exposed its transcript segment" }
    )
    let transcriptSegment = try #require(
      Self.accessibilityElements(in: presentedView)
        .first { $0.accessibilityLabel == "Follow along" }
    )
    #expect(transcriptSegment.accessibilityValue == "Current text block")
  }

  @Test(
    "transcription action mirrors the episode toolbar",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func transcriptionActionMirrorsEpisodeToolbar() async throws {
    let episode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Play Bar Transcription")
    )
    Container.shared.transcriptionAvailability().$state.new(.available)
    Container.shared.stateManager().setOnDeck(episode)

    let window = try Self.makeWindow(PlayBarSheet(viewModel: PlayBarViewModel()))
    defer { window.isHidden = true }

    let expectedActions = ["Share Episode", "Transcribe", "Rate Episode"]
    try await Wait.until(
      maxAttempts: 100,
      { @MainActor in
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        let labels = Set(
          Self.accessibilityElements(in: window).compactMap(\.accessibilityLabel)
        )
        return expectedActions.allSatisfy(labels.contains)
      },
      { @MainActor in "Play bar did not expose Share, Transcribe, and Rate actions" }
    )

    let orderedActions = Self.accessibilityElements(in: window)
      .filter { element in
        guard let label = element.accessibilityLabel else { return false }
        return expectedActions.contains(label)
      }
      .sorted { $0.accessibilityFrame.minX < $1.accessibilityFrame.minX }
      .compactMap(\.accessibilityLabel)
    #expect(orderedActions == expectedActions)

    let transcribeButton = try #require(
      Self.accessibilityElements(in: window)
        .first { $0.accessibilityLabel == "Transcribe" }
    )
    #expect(transcribeButton.accessibilityActivate())

    let transcriptionQueue = Container.shared.transcriptionQueue()
    try await Wait.until(
      maxAttempts: 100,
      { @MainActor in
        transcriptionQueue.status(for: episode.id, hasTranscript: false).canPause
      },
      { @MainActor in "Play bar transcription action did not enqueue the episode" }
    )
  }
}
