#if DEBUG && targetEnvironment(simulator)
// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container: @retroactive AutoRegistering {
  public func autoRegister() {
    appDB.context(.preview) { AppDB.inMemory() }.scope(.cached)

    // Fatal network protection for previews - ensures no actual network requests
    let previewFetcher = FakeDataFetchable()
    previewFetcher.setDefaultHandler { url in
      Assert.fatal(
        """
        ❌ FATAL: Attempted network request in SwiftUI Preview!
        URL: \(url)

        Previews should only use local/cached data. This indicates:
        1. Missing mock data registration
        2. Code path bypassing preview data sources
        3. Improper dependency injection setup

        Fix by ensuring all preview data is pre-loaded and network dependencies are mocked.
        """
      )
    }
    feedManagerSession.context(.preview) { previewFetcher }
    searchServiceSession.context(.preview) { previewFetcher }
    shareServiceSession.context(.preview) { previewFetcher }
    cacheManagerSession.context(.preview) { previewFetcher }
    podcastFeedSession.context(.preview) { previewFetcher }
    podcastOPMLSession.context(.preview) { previewFetcher }
  }
}
#endif
