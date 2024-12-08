// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import OPML
import UniformTypeIdentifiers

@Observable @MainActor final class OPMLFile: Identifiable {
  let id = UUID()
  let title: String
  var totalCount: Int {
    failed.count
      + alreadySubscribed.count
      + waiting.count
      + downloading.count
      + finished.count
  }
  var inProgressCount: Int {
    waiting.count + downloading.count
  }
  var successCount: Int {
    alreadySubscribed.count + finished.count
  }
  var failed: Set<OPMLOutline> = []
  var alreadySubscribed: Set<OPMLOutline> = []
  var waiting: Set<OPMLOutline> = []
  var downloading: Set<OPMLOutline> = []
  var finished: Set<OPMLOutline> = []

  init(title: String) {
    self.title = title
  }
}

@Observable @MainActor
final class OPMLOutline: Equatable, Hashable, Identifiable {
  enum Status {
    case failed, alreadySubscribed, waiting, downloading, finished
  }

  let id = UUID()
  var status: Status
  var feedURL: URL
  var text: String

  convenience init(status: Status, text: String) {
    self.init(
      status: status,
      feedURL: URL(string: "https://google.com")!,
      text: text
    )
  }

  init(status: Status, feedURL: URL, text: String) {
    self.status = status
    self.feedURL = feedURL
    self.text = text
  }

  nonisolated static func == (lhs: OPMLOutline, rhs: OPMLOutline) -> Bool {
    lhs.id == rhs.id
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

@Observable @MainActor final class OPMLViewModel {
  private let repository: PodcastRepository
  private var downloadManager: DownloadManager?
  let opmlType = UTType(filenameExtension: "opml", conformingTo: .xml)!
  var opmlImporting = false
  var opmlFile: OPMLFile?

  init(repository: PodcastRepository = .shared) {
    self.repository = repository
  }

  func opmlFileImporterCompletion(_ result: Result<URL, any Error>) {
    switch result {
    case .success(let url):
      if url.startAccessingSecurityScopedResource() {
        if let opml = importOPMLFile(url) {
          downloadOPMLFile(opml)
        }
      } else {
        Alert.shared("Couldn't start accessing security scoped response")
      }
      url.stopAccessingSecurityScopedResource()
    case .failure(let error):
      Alert.shared("Couldn't import OPML file: \(error)")
    }
  }

  func importOPMLFile(_ url: URL) -> OPML? {
    guard let opml = try? OPML(file: url) else {
      Alert.shared("Couldn't parse OPML file")
      return nil
    }
    if opml.entries.isEmpty {
      Alert.shared("OPML file has no subscriptions")
      return nil
    }
    return opml
  }

  func stopDownloading() {
    Task {
      if let downloadManager = downloadManager {
        await downloadManager.cancelAllDownloads()
      }
      opmlFile = nil
      Navigation.shared.currentTab = .podcasts
    }
  }

  // MARK: - Private Methods

  private func downloadOPMLFile(_ opml: OPML) {
    let opmlFile = OPMLFile(title: opml.title ?? "Podcast Subscriptions")
    for entry in opml.entries {
      guard let feedURL = entry.feedURL,
        let validURL = try? feedURL.convertToValidURL()
      else {
        opmlFile.failed.insert(OPMLOutline(status: .failed, text: entry.text))
        continue
      }
      opmlFile.waiting.insert(
        OPMLOutline(
          status: .waiting,
          feedURL: validURL,
          text: entry.text
        )
      )
    }
    self.opmlFile = opmlFile
    Task {
      downloadManager = createDownloadManager()
      guard let downloadManager = downloadManager else {
        fatalError("DownloadManager should be set now")
      }
      var taskAndOutline = [(OPMLOutline, DownloadTask)](
        capacity: opmlFile.waiting.count
      )
      for outline in opmlFile.waiting {
        let task = await downloadManager.addURL(outline.feedURL)
        taskAndOutline.append((outline, task))
      }
      for (outline, downloadTask) in taskAndOutline {
        Task {
          await downloadTask.downloadBegan()
          outline.status = .downloading
          opmlFile.waiting.remove(outline)
          opmlFile.downloading.insert(outline)
          if case .success(let data) = await downloadTask.downloadFinished(),
            case .success(let feed) = await PodcastFeed.parse(data: data.data)
          {
            outline.feedURL = feed.feedURL ?? outline.feedURL
            outline.text = feed.title ?? outline.text
            let feedURL = outline.feedURL
            if (try? await repository.db.read({ db in
              try Podcast.filter(key: ["feedURL": feedURL]).fetchOne(db)
            })) != nil {
              outline.status = .alreadySubscribed
              opmlFile.downloading.remove(outline)
              opmlFile.alreadySubscribed.insert(outline)
            } else if let unsavedPodcast = try? UnsavedPodcast(
              feedURL: outline.feedURL,
              title: outline.text,
              link: feed.link,
              image: feed.image,
              description: feed.description
            ), (try? repository.insert(unsavedPodcast)) != nil {
              if let image = feed.image {
                PodcastImages.shared.prefetch([image])
              }
              outline.status = .finished
              opmlFile.downloading.remove(outline)
              opmlFile.finished.insert(outline)
            }
          }
          if outline.status == .downloading {
            outline.status = .failed
            opmlFile.downloading.remove(outline)
            opmlFile.failed.insert(outline)
          }
        }
      }
    }
  }

  private func createDownloadManager() -> DownloadManager {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    let timeout = Double(10)
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    return DownloadManager(
      session: URLSession(configuration: configuration)
    )
  }

  // MARK: - Simulator Methods

  #if DEBUG
    public func importOPMLFileInSimulator(_ resource: String) {
      let url = Bundle.main.url(
        forResource: resource,
        withExtension: "opml"
      )!
      if let opml = importOPMLFile(url) {
        downloadOPMLFile(opml)
      }
    }
  #endif
}
