import CryptoKit
import Foundation
import RegexBuilder

extension String {
  func sha1() -> String {
    Insecure.SHA1.hash(data: Data(self.utf8)).compactMap { String(format: "%02x", $0) }.joined()
  }

  func isHTML() -> Bool {
    self.contains(
      Regex {
        ChoiceOf {
          Regex {
            "</"
          }
          Regex {
            "/>"
          }
        }
      }
    )
  }
}
