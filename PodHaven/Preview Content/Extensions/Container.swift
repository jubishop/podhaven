#if DEBUG
// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke

extension Container {
  func registerPreviewDefaults() {
    appDB.context(.preview) { AppDB.inMemory() }.scope(.cached)

    iTunesServiceSession.context(.preview) { PreviewHelpers.dataFetcher }
    cacheManagerSession.context(.preview) { PreviewHelpers.dataFetcher }
    podcastFeedSession.context(.preview) { PreviewHelpers.dataFetcher }
    podcastOPMLSession.context(.preview) { PreviewHelpers.dataFetcher }

    imagePipeline.context(.preview) {
      ImagePipeline(configuration: ImagePipeline.Configuration(dataLoader: self.fakeDataLoader()))
    }
    .scope(.cached)
  }
}
#endif
