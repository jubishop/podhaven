// Copyright Justin Bishop, 2025

import Foundation

extension URLSession {
  func validatedData(from url: URL) async throws(DownloadError) -> Data {
    do {
      let (data, response) = try await data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw DownloadError.notHTTPURLResponse(url)
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        throw DownloadError.notOKResponseCode(code: httpResponse.statusCode, url: url)
      }
      return data
    } catch is CancellationError {
      throw DownloadError.cancelled(url)
    } catch let error as DownloadError {
      throw error
    } catch {
      throw DownloadError.caught(error)
    }
  }

  func validatedData(for request: URLRequest) async throws(DownloadError) -> Data {
    guard let url = request.url
    else { throw DownloadError.invalidRequest(request) }

    do {
      let (data, response) = try await data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw DownloadError.notHTTPURLResponse(url)
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        throw DownloadError.notOKResponseCode(code: httpResponse.statusCode, url: url)
      }
      return data
    } catch is CancellationError {
      throw DownloadError.cancelled(url)
    } catch let error as DownloadError {
      throw error
    } catch {
      throw DownloadError.caught(error)
    }
  }
}
