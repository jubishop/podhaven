#if DEBUG
// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke
import SwiftUI
import ConcurrencyExtras

extension Container {
  var fakeDataLoader: Factory<FakeDataLoader> {
    Factory(self) { FakeDataLoader() }.scope(.cached)
  }
}

struct FakeDataLoader: DataLoading {
  typealias DataHandler = @Sendable (URL) async throws -> Data

  let loadedURLs = ThreadSafe<Set<URL>>([])

  private let defaultHandler = ThreadSafe<DataHandler?>(nil)
  private let fakeHandlers = ThreadSafe<[URL: DataHandler]>([:])

  // MARK: - DataLoading

  private final class TaskCancellable<Success: Sendable, Failure: Error>: Cancellable {
    private let task: Task<Success, Failure>

    init(task: Task<Success, Failure>) {
      self.task = task
    }

    func cancel() {
      task.cancel()
    }
  }

  func loadData(
    with request: URLRequest,
    didReceiveData: @escaping (Data, URLResponse) -> Void,
    completion: @escaping ((any Error)?) -> Void
  ) -> any Cancellable {
    let url = request.url!
    loadedURLs { set in set.insert(url) }

    let callbacks = UncheckedSendable((didReceiveData: didReceiveData, completion: completion))
    let task = Task {
      if let fakeHandler = fakeHandlers[url] ?? defaultHandler() {
        let fakeData = try await fakeHandler(url)
        try Task.checkCancellation()
        callbacks.didReceiveData(
          fakeData,
          HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )!
        )
        callbacks.completion(nil)
      } else {
        callbacks.completion(URLError(.fileDoesNotExist))
      }
    }

    return TaskCancellable(task: task)
  }

  // MARK: - Test Helpers

  func setDefaultHandler(_ handler: @escaping DataHandler) {
    defaultHandler(handler)
  }

  func clearCustomHandler(for url: URL) {
    fakeHandlers { dict in dict.removeValue(forKey: url) }
  }

  func respond(to url: URL, with handler: @escaping DataHandler) {
    fakeHandlers[url] = handler
  }

  func respond(to url: URL, data: Data) {
    respond(to: url) { url in data }
  }

  func respond(to url: URL, error: any Error) {
    respond(to: url) { _ in throw error }
  }

  static func create(_ url: URL) -> UIImage {
    createSolidColor(expectedColor(for: url))
  }

  static func createSolidColor(_ color: UIColor) -> UIImage {
    let size = CGSize(width: 100, height: 100)
    return UIGraphicsImageRenderer(size: size)
      .image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
      }
  }

  static func expectedColor(for url: URL) -> UIColor {
    let hash = abs(url.absoluteString.hashValue)
    return UIColor(
      red: CGFloat((hash >> 16) & 0xFF) / 255.0,
      green: CGFloat((hash >> 8) & 0xFF) / 255.0,
      blue: CGFloat(hash & 0xFF) / 255.0,
      alpha: 1.0
    )
  }

  static func pixelColor(of image: UIImage) -> UIColor? {
    guard let cgImage = image.cgImage else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixelData = [UInt8](repeating: 0, count: 4)

    guard
      let context = unsafe CGContext(
        data: &pixelData,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    // Sample center pixel
    context.draw(
      cgImage,
      in: CGRect(
        x: -CGFloat(width / 2),
        y: -CGFloat(height / 2),
        width: CGFloat(width),
        height: CGFloat(height)
      )
    )

    return UIColor(
      red: CGFloat(pixelData[0]) / 255.0,
      green: CGFloat(pixelData[1]) / 255.0,
      blue: CGFloat(pixelData[2]) / 255.0,
      alpha: CGFloat(pixelData[3]) / 255.0
    )
  }

  static func colorsApproximatelyEqual(
    _ color1: UIColor?,
    _ color2: UIColor?,
    tolerance: CGFloat = 0.02
  ) -> Bool {
    guard let color1, let color2 else { return false }

    var r1: CGFloat = 0
    var g1: CGFloat = 0
    var b1: CGFloat = 0
    var a1: CGFloat = 0
    var r2: CGFloat = 0
    var g2: CGFloat = 0
    var b2: CGFloat = 0
    var a2: CGFloat = 0

    unsafe color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    unsafe color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

    return abs(r1 - r2) <= tolerance
      && abs(g1 - g2) <= tolerance
      && abs(b1 - b2) <= tolerance
      && abs(a1 - a2) <= tolerance
  }
}
#endif
