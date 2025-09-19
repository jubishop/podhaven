// Copyright Justin Bishop, 2025

import SwiftUI
import UIKit

extension UIFont.TextStyle {
  init(_ textStyle: Font.TextStyle) {
    switch textStyle {
    case .largeTitle:
      self = .largeTitle
    case .title:
      self = .title1
    case .title2:
      self = .title2
    case .title3:
      self = .title3
    case .headline:
      self = .headline
    case .subheadline:
      self = .subheadline
    case .body:
      self = .body
    case .callout:
      self = .callout
    case .caption:
      self = .caption1
    case .caption2:
      self = .caption2
    case .footnote:
      self = .footnote
    @unknown default:
      self = .body
    }
  }
}
