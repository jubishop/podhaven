// Copyright Justin Bishop, 2025

import Foundation

extension URLSession: DataFetchable {
  func validatedData(from url: URL) async throws(DownloadError) -> Data {
    do {
      let (data, response) = try await data(from: url)
      if let httpResponse = response as? HTTPURLResponse {
        guard (200...299).contains(httpResponse.statusCode)
        else { throw DownloadError.notOKResponseCode(code: httpResponse.statusCode, url: url) }
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
      if let httpResponse = response as? HTTPURLResponse {
        guard (200...299).contains(httpResponse.statusCode)
        else { throw DownloadError.notOKResponseCode(code: httpResponse.statusCode, url: url) }
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

  func scheduleDownload(_ request: URLRequest) async -> Int {
    let task = downloadTask(with: request)
    task.resume()
    return task.taskIdentifier
  }

  func listDownloadTaskIDs() async -> [Int] {
    return await allTasks.map { $0.taskIdentifier }
  }

  func cancelDownload(taskID: Int) async {
    await allTasks.first(where: { $0.taskIdentifier == taskID })?.cancel()
  }
}
