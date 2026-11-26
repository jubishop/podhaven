// Copyright Justin Bishop, 2026

import Foundation

struct RemoteOPMLError: Error, LocalizedError, Sendable {
  var errorDescription: String? {
    """
    PodHaven can't import an OPML list from a link. Download the OPML file, then share the \
    file with PodHaven or import it from Settings → OPML.
    """
  }
}
