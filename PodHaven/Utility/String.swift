import Foundation
import RegexBuilder

extension String {
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
