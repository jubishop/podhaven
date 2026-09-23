// Copyright Justin Bishop, 2026

import Foundation
import Sentry
import Testing
import zlib

@testable import PodHaven

final class SentryEnvelopeCapture {
  struct Item {
    let header: [String: Any]
    let data: Data
  }

  private final class CaptureProtocol: URLProtocol, @unchecked Sendable {
    static let requests = ThreadSafe<[String: ThreadSafe<[Data]>]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      var body = request.httpBody
      if body == nil, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          guard count > 0 else { break }
          data.append(contentsOf: buffer.prefix(count))
        }
        body = data
      }
      if let host = request.url?.host, let body {
        Self.requests[host]? { $0.append(body) }
      } else {
        Issue.record("Sentry request had no host or body")
      }
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data("{}".utf8))
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
  }

  let client: SentryClient
  private let host = UUID().uuidString.lowercased() + ".invalid"
  private let requests = ThreadSafe<[Data]>([])
  private let cache = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  private let session: URLSession

  init(options: Sentry.Options) throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CaptureProtocol.self]
    session = URLSession(configuration: configuration)
    options.urlSession = session
    options.dsn = "https://test@\(host)/1"
    options.cacheDirectoryPath = cache.path
    options.sendClientReports = false
    options.enableAutoSessionTracking = false
    CaptureProtocol.requests[host] = requests
    client = try #require(SentryClient(options: options))
  }

  deinit {
    client.close()
    session.invalidateAndCancel()
    CaptureProtocol.requests[host] = nil
    try? FileManager.default.removeItem(at: cache)
  }

  func items() async throws -> [Item] {
    defer { withExtendedLifetime(self) {} }
    let body: Data
    do {
      body = try await Wait.forValue { [requests] in requests().first }
    } catch {
      let paths = FileManager.default.enumerator(atPath: cache.path)?.allObjects ?? []
      let tasks = await session.allTasks
      let taskStates = tasks.map { task in
        "state=\(task.state.rawValue) sent=\(task.countOfBytesSent) received=\(task.countOfBytesReceived) error=\(String(describing: task.error))"
      }
      Issue.record("No envelope request for \(host); cache entries: \(paths); tasks: \(taskStates)")
      throw error
    }
    var data = body
    if body.starts(with: [0x1f, 0x8b]) {
      var stream = z_stream()
      #expect(
        inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
          == Z_OK
      )
      defer { inflateEnd(&stream) }
      var decoded = Data(count: 2 * 1024 * 1024)
      let capacity = decoded.count
      let status = body.withUnsafeBytes { input in
        decoded.withUnsafeMutableBytes { output in
          stream.next_in = UnsafeMutablePointer(
            mutating: input.bindMemory(to: Bytef.self).baseAddress!
          )
          stream.avail_in = uInt(body.count)
          stream.next_out = output.bindMemory(to: Bytef.self).baseAddress!
          stream.avail_out = uInt(capacity)
          return inflate(&stream, Z_FINISH)
        }
      }
      #expect(status == Z_STREAM_END)
      decoded.count = Int(stream.total_out)
      data = decoded
    }
    var cursor = try #require(data.firstIndex(of: 0x0a)) + 1
    var items: [Item] = []
    while cursor < data.count {
      let end = try #require(data[cursor...].firstIndex(of: 0x0a))
      let header = try #require(
        JSONSerialization.jsonObject(with: data[cursor..<end]) as? [String: Any]
      )
      let length = try #require(header["length"] as? Int)
      let start = end + 1
      #expect(start + length <= data.count)
      items.append(Item(header: header, data: data.subdata(in: start..<(start + length))))
      cursor = start + length + 1
    }
    return items
  }
}
