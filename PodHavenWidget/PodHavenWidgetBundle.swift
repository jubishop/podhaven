// Copyright Justin Bishop, 2026

import SwiftUI
import WidgetKit

@main
struct PodHavenWidgetBundle: WidgetBundle {
  var body: some Widget {
    NowPlayingWidget()
    QueueWidget()
  }
}
