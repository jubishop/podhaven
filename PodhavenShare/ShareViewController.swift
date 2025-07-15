// Copyright Justin Bishop, 2025

import OSLog
import UIKit

class ShareViewController: UIViewController {
  private let log = Logger(subsystem: "PodHaven", category: "Share")

  override func viewDidLoad() {
    super.viewDidLoad()
    log.debug("Hello from ShareViewController!")
  }
}

