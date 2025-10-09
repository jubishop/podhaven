// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SquareImage: View {
  enum SizeConstraint {
    case both
    case width
    case height
  }

  enum ImageSource {
    case url(URL)
    case uiImage(UIImage?)
  }

  enum SizingMode {
    case selfSizing(Binding<CGFloat>?, SizeConstraint)
    case fixed(CGFloat)
    case fillParent

    static func selfSizing(
      size: Binding<CGFloat>? = nil,
      constraint: SizeConstraint = .both
    ) -> SizingMode {
      .selfSizing(size, constraint)
    }

    var needsExplicitFrame: Bool {
      switch self {
      case .selfSizing, .fixed:
        return true
      case .fillParent:
        return false
      }
    }

    var sizeConstraint: SizeConstraint {
      switch self {
      case .selfSizing(_, let constraint):
        return constraint
      case .fixed, .fillParent:
        return .both
      }
    }

    var updatesFromGeometry: Bool {
      switch self {
      case .selfSizing, .fillParent:
        return true
      case .fixed:
        return false
      }
    }
  }

  @State private var internalSize: CGFloat = 100

  private let imageSource: ImageSource
  private let cornerRadius: CGFloat
  private let sizingMode: SizingMode
  private let placeholderIcon: AppIcon

  private var size: Binding<CGFloat> {
    switch sizingMode {
    case .selfSizing(let externalSize, _):
      return externalSize ?? $internalSize
    case .fillParent:
      return $internalSize
    case .fixed(let value):
      return .constant(value)
    }
  }

  private var currentSize: CGFloat {
    switch sizingMode {
    case .fixed(let value):
      return value
    default:
      return size.wrappedValue
    }
  }

  private init(
    imageSource: ImageSource,
    cornerRadius: CGFloat = 8,
    sizing: SizingMode = .selfSizing(),
    placeholderIcon: AppIcon = .noImage
  ) {
    self.imageSource = imageSource
    self.cornerRadius = cornerRadius
    self.sizingMode = sizing
    self.placeholderIcon = placeholderIcon
  }

  init(
    image: URL,
    cornerRadius: CGFloat = 8,
    sizing: SizingMode = .selfSizing(),
    placeholderIcon: AppIcon = .noImage
  ) {
    self.init(
      imageSource: .url(image),
      cornerRadius: cornerRadius,
      sizing: sizing,
      placeholderIcon: placeholderIcon
    )
  }

  init(
    image: UIImage?,
    cornerRadius: CGFloat = 8,
    sizing: SizingMode = .selfSizing(),
    placeholderIcon: AppIcon = .noImage
  ) {
    self.init(
      imageSource: .uiImage(image),
      cornerRadius: cornerRadius,
      sizing: sizing,
      placeholderIcon: placeholderIcon
    )
  }

  var body: some View {
    Group {
      switch imageSource {
      case .url(let url):
        PodLazyImage(url: url) { state in
          if let image = state.image {
            image
              .resizable()
              .cornerRadius(cornerRadius)
          } else {
            placeholderView
          }
        }
      case .uiImage(let uiImage):
        if let uiImage {
          Image(uiImage: uiImage)
            .resizable()
            .cornerRadius(cornerRadius)
        } else {
          placeholderView
        }
      }
    }
    .aspectRatio(1, contentMode: .fill)
    .onGeometryChange(for: CGSize.self) { geometry in
      geometry.size
    } action: { newSize in
      guard sizingMode.updatesFromGeometry else { return }
      let newValue =
        switch sizingMode.sizeConstraint {
        case .both: min(newSize.width, newSize.height)
        case .width: newSize.width
        case .height: newSize.height
        }
      if newValue > 0, currentSize != newValue {
        size.wrappedValue = newValue
      }
    }
    .frame(
      width: sizingMode.needsExplicitFrame && sizingMode.sizeConstraint != .width
        ? currentSize : nil,
      height: sizingMode.needsExplicitFrame && sizingMode.sizeConstraint != .height
        ? currentSize : nil
    )
    .clipped()
  }

  func selectable(
    isSelected: Binding<Bool>,
    isSelecting: Bool
  ) -> some View {
    self
      .overlay {
        if isSelecting {
          Rectangle()
            .fill(Color.black.opacity(isSelected.wrappedValue ? 0.0 : 0.5))
            .cornerRadius(cornerRadius)
            .allowsHitTesting(false)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if isSelecting {
          let buttonSize = max(24, currentSize * 0.2)
          let buttonPadding = max(8, currentSize * 0.08)
          Button(
            action: {
              isSelected.wrappedValue.toggle()
            },
            label: {
              (isSelected.wrappedValue ? AppIcon.selectionFilled : AppIcon.selectionEmpty)
                .image
                .font(.system(size: buttonSize))
                .foregroundColor(isSelected.wrappedValue ? .blue : .white)
                .background(
                  Circle()
                    .fill(Color.black.opacity(0.5))
                    .padding(-3)
                )
            }
          )
          .buttonStyle(.borderless)
          .padding(buttonPadding)
        }
      }
  }

  private var placeholderView: some View {
    ZStack {
      Color(.secondarySystemFill)
        .cornerRadius(cornerRadius)
      placeholderIcon.coloredImage
        .font(.system(size: currentSize / 2))
        .frame(width: currentSize / 2, height: currentSize / 2)
    }
  }
}
