// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import OrderedCollections
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

private let supportsHostedAccessibilityInspection = ProcessInfo.processInfo.isiOSAppOnMac

@Suite("Circular progress ring", .container)
@MainActor struct CircularProgressViewTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  // MARK: - Sectors

  @Test(
    "a single progress value fills its share of the circle and never more",
    arguments: [
      (0.0, nil), (0.000001, 0.000001), (0.5, 0.5), (1.0, 1.0), (1.1, 1.0), (-0.5, nil),
      (Double.nan, nil), (Double.infinity, nil), (-Double.infinity, nil),
    ] as [(Double, Double?)]
  )
  func singleSector(value: Double, expectedEnd: Double?) throws {
    let sectors = ProgressRingSector.sectors(total: 1, amounts: [.blue: value])

    guard let expectedEnd else {
      #expect(sectors.isEmpty)
      return
    }
    let sector = try #require(sectors[.blue])
    #expect(sectors.count == 1)
    #expect(sector.start == 0)
    #expect(abs(sector.end - expectedEnd) < 1e-12)
  }

  @Test(
    "an invalid total lets valid sectors share the whole circle",
    arguments: [0, -1, Double.nan, Double.infinity, -Double.infinity]
  )
  func invalidTotal(total: Double) throws {
    let sectors = ProgressRingSector.sectors(total: total, amounts: [.green: 1, .blue: 3])

    #expect(Array(sectors.keys) == [.green, .blue])
    let green = try #require(sectors[.green])
    let blue = try #require(sectors[.blue])
    #expect(green.start == 0)
    #expect(abs(green.end - 0.25) < 1e-12)
    #expect(blue.start == green.end)
    #expect(abs(blue.end - 1) < 1e-12)
  }

  @Test("multi-sector progress keeps order, omits empty and invalid sectors, and stays in bounds")
  func multipleSectors() throws {
    let partial = ProgressRingSector.sectors(
      total: 10,
      amounts: [.green: 3, .blue: 0, .red: 1, .orange: .nan, .purple: -3]
    )
    #expect(Array(partial.keys) == [.green, .red])
    #expect(abs((try #require(partial[.green])).end - 0.3) < 1e-12)
    #expect(abs((try #require(partial[.red])).end - 0.4) < 1e-12)

    for amounts: OrderedDictionary<Color, Double> in [
      [.green: 1, .blue: 1],
      [.green: .greatestFiniteMagnitude, .blue: .greatestFiniteMagnitude],
      [.green: 3, .blue: 2, .red: 1],
    ] {
      let sectors = ProgressRingSector.sectors(total: 1, amounts: amounts)
      #expect(Array(sectors.keys) == Array(amounts.keys))
      #expect(abs((sectors.values.last?.end ?? 0) - 1) < 1e-12)
    }

    let inputs: [Double] = [
      0, 1e-300, 0.000001, 0.25, 1, 3, 1e300, .greatestFiniteMagnitude, -1, .nan, .infinity,
    ]
    for total in inputs {
      for first in inputs {
        for second in inputs {
          let sectors = ProgressRingSector.sectors(
            total: total,
            amounts: [.green: first, .blue: second, .red: 1]
          )
          var previousEnd = 0.0
          for sector in sectors.values {
            #expect(sector.start.isFinite && sector.end.isFinite)
            #expect(sector.start == previousEnd)
            #expect(sector.end > sector.start)
            #expect(sector.end <= 1)
            previousEnd = sector.end
          }
        }
      }
    }
  }

  // MARK: - Geometry

  @Test(
    "every sector path stays inside its ring and angular range",
    arguments: [12.0, 28.0, 180.0],
    [0.0, 0.3, 0.9]
  )
  func pathStaysInsideRing(size: Double, start: Double) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outerRadius = size / 2
    let innerRadius = outerRadius * 0.4
    let tolerance = 0.0001
    // Cubic Bézier arcs bulge past their circle by a small fraction of the radius.
    let curveTolerance = outerRadius * 0.0003

    for fraction in [1e-12, 1e-6, 0.001, 0.01, 0.03, 0.05, 0.1, 0.25, 0.5, 0.75, 0.99, 0.99993, 1] {
      let sector = ProgressRingSector(start: start, end: min(start + fraction, 1))
      let path = sector.path(in: rect, innerRadiusRatio: 0.4)
      guard !path.isEmpty else { continue }

      #expect(
        rect.insetBy(dx: -curveTolerance, dy: -curveTolerance)
          .contains(path.cgPath.boundingBoxOfPath)
      )
      let startAngle = sector.start * 2 * .pi - .pi / 2
      let sweep = (sector.end - sector.start) * 2 * .pi
      for point in Self.endpoints(of: path) {
        #expect(point.x.isFinite && point.y.isFinite)
        let radius = hypot(point.x - center.x, point.y - center.y)
        #expect(radius >= innerRadius - tolerance && radius <= outerRadius + tolerance)
        guard sweep < 2 * .pi else { continue }
        var angle = atan2(point.y - center.y, point.x - center.x) - startAngle
        angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if angle < -tolerance { angle += 2 * .pi }
        #expect(
          angle >= -tolerance && angle <= sweep + tolerance,
          "Sector \(sector.start)...\(sector.end) at \(size) pt drew outside its range"
        )
      }
    }
  }

  @Test(
    "gaps remove slivers instead of inverting them",
    arguments: [
      (12.0, 0.05, true), (28.0, 0.01, true), (28.0, 0.05, false), (180.0, 0.000001, true),
      (180.0, 0.01, false),
    ]
  )
  func gapsRemoveSlivers(size: Double, fraction: Double, isEmpty: Bool) {
    let path = ProgressRingSector(start: 0.2, end: 0.2 + fraction)
      .path(in: CGRect(x: 0, y: 0, width: size, height: size), innerRadiusRatio: 0.4)

    #expect(path.isEmpty == isEmpty)
  }

  @Test(
    "adjacent sectors keep the gap Charts drew at row, detail, and full-width sizes",
    arguments: [(12.0, 1.0), (28.0, 1.0), (180.0, 2.0)]
  )
  func gapWidth(size: Double, edgeInset: Double) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let right = ProgressRingSector(start: 0, end: 0.5).path(in: rect, innerRadiusRatio: 0.4)
    let left = ProgressRingSector(start: 0.5, end: 1).path(in: rect, innerRadiusRatio: 0.4)

    #expect(abs(right.cgPath.boundingBoxOfPath.minX - (rect.midX + edgeInset)) < 0.0001)
    #expect(abs(left.cgPath.boundingBoxOfPath.maxX - (rect.midX - edgeInset)) < 0.0001)
  }

  @Test("only complete progress closes the gap into a whole ring", arguments: [12.0, 28.0, 180.0])
  func completeRing(size: Double) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let top = CGPoint(x: rect.midX, y: size * 0.05)
    let center = CGPoint(x: rect.midX, y: rect.midY)

    let complete = ProgressRingSector(start: 0, end: 1).path(in: rect, innerRadiusRatio: 0.4)
    #expect(abs(complete.cgPath.boundingBoxOfPath.width - size) < 0.0001)
    #expect(abs(complete.cgPath.boundingBoxOfPath.height - size) < 0.0001)
    #expect(complete.contains(top))
    #expect(!complete.contains(center))

    let almost = ProgressRingSector(start: 0, end: 0.99993).path(in: rect, innerRadiusRatio: 0.4)
    #expect(!almost.isEmpty)
    #expect(!almost.contains(top))
  }

  @Test("invalid geometry inputs draw nothing or stay inside the ring")
  func invalidGeometry() {
    let rect = CGRect(x: 0, y: 0, width: 28, height: 28)
    #expect(ProgressRingSector(start: 0, end: 0.5).path(in: .zero, innerRadiusRatio: 0.4).isEmpty)
    #expect(
      ProgressRingSector(start: 0, end: 0.5)
        .path(in: CGRect(x: 0, y: 0, width: Double.nan, height: 28), innerRadiusRatio: 0.4)
        .isEmpty
    )
    #expect(
      ProgressRingSector(start: 0, end: 0.5)
        .path(in: CGRect(x: 0, y: 0, width: 1, height: 1), innerRadiusRatio: 0.4)
        .isEmpty
    )
    #expect(ProgressRingSector(start: .nan, end: 0.5).path(in: rect, innerRadiusRatio: 0.4).isEmpty)
    #expect(ProgressRingSector(start: 0.6, end: 0.5).path(in: rect, innerRadiusRatio: 0.4).isEmpty)

    let overshoot = ProgressRingSector(start: -0.2, end: 1.3).path(in: rect, innerRadiusRatio: 0.4)
    #expect(abs(overshoot.cgPath.boundingBoxOfPath.width - rect.width) < 0.0001)
    #expect(abs(overshoot.cgPath.boundingBoxOfPath.height - rect.height) < 0.0001)

    for ratio in [-1, 2, Double.nan, Double.infinity] {
      let path = ProgressRingSector(start: 0, end: 0.5).path(in: rect, innerRadiusRatio: ratio)
      #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(path.cgPath.boundingBoxOfPath))
      #expect(Self.endpoints(of: path).allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
  }

  // MARK: - Accessibility

  @Test(
    "playback ring is one decorative element with its progress value",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func playbackAccessibility() async throws {
    let episode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(),
      unsavedEpisode: try Create.unsavedEpisode(
        duration: .seconds(100),
        currentTime: .seconds(25)
      )
    )

    try await Self.expectSingleElement(
      StatusIconColumn(episode: episode, iconSpacing: 4, iconSize: 12),
      label: "Playback Progress",
      value: "25%"
    )
  }

  @Test(
    "download ring is one decorative element with its progress value",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    ),
    arguments: [(false, "Download Progress"), (true, "Save Progress")]
  )
  func downloadAccessibility(saveInCache: Bool, label: String) async throws {
    let saved = try await Create.podcastEpisode(
      try Create.unsavedEpisode(saveInCache: saveInCache)
    )
    try await repo.updateDownloading(saved.id, downloading: true)
    sharedState.updateDownloadProgress(for: saved.id, progress: 0.4)
    let episode = try #require(try await repo.podcastEpisode(saved.id))

    try await Self.expectSingleElement(
      StatusIconColumn(episode: episode, iconSpacing: 10, iconSize: 28),
      label: label,
      value: "40%"
    )
  }

  @Test(
    "OPML import ring is one decorative element with its counts",
    .enabled(
      if: supportsHostedAccessibilityInspection,
      "SwiftUI does not expose hosted accessibility elements in iOS Simulator"
    )
  )
  func opmlAccessibility() async throws {
    let file = OPMLFile(title: "Import")
    file.finished = [
      OPMLOutline(status: .finished, text: "One"), OPMLOutline(status: .finished, text: "Two"),
    ]
    file.downloading = [OPMLOutline(status: .downloading, text: "Three")]
    file.waiting = [OPMLOutline(status: .waiting, text: "Four")]
    file.failed = [OPMLOutline(status: .failed, text: "Five")]

    try await Self.expectSingleElement(
      VStack { OPMLImportSheet(viewModel: Container.shared.opmlViewModel(), opmlFile: file) },
      label: "Import Progress",
      value: "2 completed, 1 downloading, 1 waiting, 1 failed"
    )
  }

  // MARK: - Helpers

  private static func expectSingleElement(
    _ view: some View,
    label: String,
    value: String
  ) async throws {
    try await withHostedTestWindow(TestHostingController(rootView: view)) { window in
      let matches = accessibilityElements(in: window).filter { $0.accessibilityLabel == label }
      #expect(matches.count == 1)
      #expect(matches.first?.accessibilityValue == value)
    }
  }

  private static func endpoints(of path: Path) -> [CGPoint] {
    var points: [CGPoint] = []
    path.forEach { element in
      switch element {
      case .move(let point), .line(let point):
        points.append(point)
      case .quadCurve(let point, _), .curve(let point, _, _):
        points.append(point)
      case .closeSubpath:
        break
      }
    }
    return points
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
