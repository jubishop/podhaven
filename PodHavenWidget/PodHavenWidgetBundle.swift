// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

@main
struct PodHavenWidgetBundle: WidgetBundle {
  init() {
    WidgetLog.info("PodHavenWidgetBundle initialized")
  }

  var body: some Widget {
    NowPlayingWidget()
    QueueWidget()
  }
}
