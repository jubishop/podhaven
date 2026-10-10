// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Nuke
import Testing
import UIKit

@testable import PodHaven

@Suite("of CarPlay artwork tests", .container)
@MainActor struct CarPlayArtworkTests {
  private static let artworkPixels = 1200

  private static func serveLargeArtwork(_ url: URL) throws {
    let size = CGSize(width: artworkPixels, height: artworkPixels)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format)
      .image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(origin: .zero, size: size))
      }
    Container.shared.fakeDataLoader().respond(to: url, data: try #require(image.pngData()))
  }

  private static func withinListImageBound(_ size: CGSize, scale: CGFloat) -> Bool {
    let bound = CPListItem.maximumImageSize
    return size.width > 0 && size.height > 0 && size.width <= bound.width * scale
      && size.height <= bound.height * scale
  }

  @Test(
    "Up Next rows receive artwork within the car's list image bound",
    arguments: [(CGFloat(1), CGFloat(1)), (CGFloat(3), CGFloat(3)), (CGFloat(0), CGFloat(3))]
  )
  func upNext(displayScale: CGFloat, boundScale: CGFloat) async throws {
    let episode = try await Create.podcastEpisode()
    try Self.serveLargeArtwork(episode.image)
    let recorder = ImagePipelineRecorder.install()
    try await Container.shared.queue().append(episode.id)
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    controller.carTraitCollection = UITraitCollection(displayScale: displayScale)
    coordinator.connect(controller)
    defer { coordinator.disconnect(controller) }
    controller.completions[0](true, nil)
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let queue = try #require(root.templates.first as? CPListTemplate)
    try await Wait.until(
      { @MainActor in (queue.sections.first?.items.first as? CPListItem)?.image != nil },
      { "Queued episode artwork must reach its row" }
    )
    try await Wait.until(
      { !recorder.pixelSizes(for: episode.image).isEmpty },
      { "The pipeline must report the delivered row artwork" }
    )
    let delivered = recorder.pixelSizes(for: episode.image)
    #expect(
      delivered.allSatisfy { Self.withinListImageBound($0, scale: boundScale) },
      "Row artwork \(delivered) exceeds \(CPListItem.maximumImageSize) at scale \(boundScale)"
    )
  }

  @Test("podcast rows receive bounded artwork without replacing full-size in-app artwork")
  func podcasts() async throws {
    let imageURL = URL.valid()
    try Self.serveLargeArtwork(imageURL)
    let recorder = ImagePipelineRecorder.install()
    _ = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Large artwork",
            image: imageURL,
            subscriptionDate: Date()
          ),
          unsavedEpisodes: [try Create.unsavedEpisode()]
        )
      )
    let scene = try CarPlayPodcastScene()
    defer { scene.stop() }
    try await Wait.until(
      { @MainActor in
        CarPlayPodcastScene.rows(scene.podcasts).first { $0.text == "Large artwork" }?.image != nil
      },
      { "Podcast artwork must reach its row" }
    )
    try await Wait.until(
      { !recorder.pixelSizes(for: imageURL).isEmpty },
      { "The pipeline must report the delivered row artwork" }
    )
    let delivered = recorder.pixelSizes(for: imageURL)
    let scale = scene.controller.carTraitCollection.displayScale
    #expect(
      delivered.allSatisfy { Self.withinListImageBound($0, scale: scale) },
      "Row artwork \(delivered) exceeds \(CPListItem.maximumImageSize) at scale \(scale)"
    )
    let inApp = try await Container.shared.imagePipeline().image(for: imageURL)
    #expect(inApp.size.width * inApp.scale == CGFloat(Self.artworkPixels))
  }
}
