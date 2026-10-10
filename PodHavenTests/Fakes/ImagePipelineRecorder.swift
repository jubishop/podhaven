// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Nuke
import UIKit

@testable import PodHaven

final class ImagePipelineRecorder: ImagePipeline.Delegate {
  private let pixelSizes = ThreadSafe<[URL: [CGSize]]>([:])

  static func install() -> ImagePipelineRecorder {
    let recorder = ImagePipelineRecorder()
    let dataLoader = Container.shared.fakeDataLoader()
    Container.shared.imagePipeline.context(.test) {
      ImagePipeline(
        configuration: ImagePipeline.Configuration(dataLoader: dataLoader),
        delegate: recorder
      )
    }
    return recorder
  }

  func pixelSizes(for url: URL) -> [CGSize] { pixelSizes[url] ?? [] }

  @ImagePipelineActor
  func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline)
  {
    guard case .finished(.success(let response)) = event, let url = task.request.url else { return }
    let image = response.image
    let size = CGSize(
      width: image.size.width * image.scale,
      height: image.size.height * image.scale
    )
    pixelSizes { $0[url, default: []].append(size) }
  }
}
