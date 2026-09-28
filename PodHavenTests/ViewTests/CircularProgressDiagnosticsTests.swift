// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("Circular progress diagnostic boundary", .container)
@MainActor struct CircularProgressDiagnosticsTests {
  @Test(
    "rendered progress retains input and effective geometry",
    arguments: [0.0, 0.000001, 0.5, 1.0, 1.1],
    [12.0, 28.0]
  )
  func capturesProgress(progress: Double, size: Double) async throws {
    let url = AppInfo.recentLogFileURL.deletingLastPathComponent()
      .appendingPathComponent("chart-progress.ndjson")
    let host = TestHostingController(
      rootView: CircularProgressView(colorAmounts: [.blue: progress])
        .frame(width: size, height: size)
    )
    try await withHostedTestWindow(host) { _ in
      try #require(FileManager.default.fileExists(atPath: url.path), "No pre-render chart evidence")
      let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        .map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
      let snapshots = try records.compactMap { record -> [String: Any]? in
        guard let metadata = record["metadata"] as? [String: String], let json = metadata["chart"]
        else { return nil }
        return try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
      }
      #expect(
        snapshots.contains {
          $0["width"] as? Double == size && $0["height"] as? Double == size
            && $0["values"] as? [Double] == [progress]
        }
      )
      #expect(records.allSatisfy { $0["sessionID"] as? String == FileLogHandler.sessionID })
    }
  }
  @Test("status column retains playback accessibility and private producer context")
  func playbackAccessibility() async throws {
    let episode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(title: "private-chart-podcast"),
      unsavedEpisode: try Create.unsavedEpisode(
        title: "private-chart-episode",
        duration: .seconds(100),
        currentTime: .seconds(25)
      )
    )
    let host = TestHostingController(
      rootView: StatusIconColumn(episode: episode, iconSpacing: 4, iconSize: 12)
        .dynamicTypeSize(.accessibility5)
    )
    try await withHostedTestWindow(host) { window in
      let elements = Self.accessibilityElements(in: window)
      let progress = try #require(elements.first { $0.accessibilityLabel == "Playback Progress" })
      #expect(progress.accessibilityValue == "25%")
      #expect(elements.filter { $0.accessibilityLabel == "Playback Progress" }.count == 1)
      let text = try String(contentsOf: ChartProgressDiagnostics.fileURL, encoding: .utf8)
      #expect(!text.contains("private-chart-podcast"))
      #expect(!text.contains("private-chart-episode"))
      #expect(text.contains("playback"))
    }
  }

  private static func accessibilityElements(in root: NSObject) -> [NSObject] {
    var visited: Set<ObjectIdentifier> = []
    func collect(_ object: NSObject) -> [NSObject] {
      guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
      var result = object.isAccessibilityElement ? [object] : []
      if let view = object as? UIView {
        result += view.subviews.flatMap(collect)
      }
      let count = object.accessibilityElementCount()
      if count != NSNotFound, count > 0 {
        for index in 0..<count {
          if let child = object.accessibilityElement(at: index) as? NSObject {
            result += collect(child)
          }
        }
      }
      return result
    }
    return collect(root)
  }

}
