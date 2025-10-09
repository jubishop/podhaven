// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct SquareImage: View {
  enum ImageSource {
    case url(URL)
    case uiImage(UIImage?)
  }

  enum SizingMode {
    case fixed(CGFloat)
    case fillParent

    var fixedDimension: CGFloat? {
      if case .fixed(let value) = self { value } else { nil }
    }
  }

  @State private var internalSize: CGFloat = 100

  private let imageSource: ImageSource
  private let cornerRadius: CGFloat
  private let sizingMode: SizingMode
  private let placeholderIcon: AppIcon

  private var currentSize: CGFloat {
    switch sizingMode {
    case .fixed(let value):
      return value
    case .fillParent:
      return internalSize
    }
  }

  private init(
    imageSource: ImageSource,
    cornerRadius: CGFloat = 8,
    sizing: SizingMode = .fillParent,
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
    sizing: SizingMode = .fillParent,
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
    sizing: SizingMode = .fillParent,
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
      if case .fillParent = sizingMode {
        let newValue = min(newSize.width, newSize.height)
        if newValue > 0, internalSize != newValue {
          internalSize = newValue
        }
      }
    }
    .frame(width: sizingMode.fixedDimension, height: sizingMode.fixedDimension)
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
