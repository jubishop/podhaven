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
    case fillParent

    static func selfSizing(
      size: Binding<CGFloat>? = nil,
      constraint: SizeConstraint = .both
    ) -> SizingMode {
      .selfSizing(size, constraint)
    }

    var isSelfSizing: Bool {
      if case .selfSizing = self { return true }
      return false
    }

    var sizeConstraint: SizeConstraint {
      if case .selfSizing(_, let constraint) = self {
        return constraint
      }
      return .both
    }
  }

  @State private var internalSize: CGFloat = 100

  private let imageSource: ImageSource
  private let cornerRadius: CGFloat
  private let sizingMode: SizingMode

  private var size: Binding<CGFloat> {
    if case .selfSizing(let externalSize, _) = sizingMode, let externalSize {
      return externalSize
    }
    return $internalSize
  }

  init(
    imageSource: ImageSource,
    cornerRadius: CGFloat = 8,
    sizing: SizingMode = .selfSizing()
  ) {
    self.imageSource = imageSource
    self.cornerRadius = cornerRadius
    self.sizingMode = sizing
  }

  init(
    image: URL,
    cornerRadius: CGFloat = 8,
    sizing: SizingMode = .selfSizing()
  ) {
    self.init(
      imageSource: .url(image),
      cornerRadius: cornerRadius,
      sizing: sizing
    )
  }

  init(
    image: UIImage?,
    cornerRadius: CGFloat = 8,
    sizing: SizingMode = .selfSizing()
  ) {
    self.init(
      imageSource: .uiImage(image),
      cornerRadius: cornerRadius,
      sizing: sizing
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
    .modifier(
      SquareImageSizing(
        size: size,
        sizingMode: sizingMode
      )
    )
  }

  private var placeholderView: some View {
    ZStack {
      Color.gray
        .cornerRadius(cornerRadius)
      VStack {
        AppIcon.noImage.coloredImage
          .font(.system(size: size.wrappedValue / 2))
          .frame(width: size.wrappedValue / 2, height: size.wrappedValue / 2)
        Text("No Image")
          .font(.caption)
          .foregroundColor(.white.opacity(0.8))
      }
    }
  }
}

// MARK: - SquareImageSizing

private struct SquareImageSizing: ViewModifier {
  let size: Binding<CGFloat>
  let sizingMode: SquareImage.SizingMode

  func body(content: Content) -> some View {
    content
      .aspectRatio(1, contentMode: .fill)
      .onGeometryChange(for: CGSize.self) { geometry in
        geometry.size
      } action: { newSize in
        size.wrappedValue =
          switch sizingMode.sizeConstraint {
          case .both: min(newSize.width, newSize.height)
          case .width: newSize.width
          case .height: newSize.height
          }
      }
      .frame(
        width: sizingMode.isSelfSizing && sizingMode.sizeConstraint != .width
          ? size.wrappedValue : nil,
        height: sizingMode.isSelfSizing && sizingMode.sizeConstraint != .height
          ? size.wrappedValue : nil
      )
      .clipped()
  }
}

// MARK: - Selectable Modifier

extension View {
  func selectable(
    isSelected: Binding<Bool>,
    isSelecting: Bool,
    cornerRadius: CGFloat = 8
  ) -> some View {
    modifier(
      SelectableModifier(
        isSelected: isSelected,
        isSelecting: isSelecting,
        cornerRadius: cornerRadius
      )
    )
  }
}

private struct SelectableModifier: ViewModifier {
  @Binding var isSelected: Bool
  let isSelecting: Bool
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .overlay {
        if isSelecting {
          Rectangle()
            .fill(Color.black.opacity(isSelected ? 0.0 : 0.5))
            .cornerRadius(cornerRadius)
            .allowsHitTesting(false)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if isSelecting {
          Button(
            action: {
              isSelected.toggle()
            },
            label: {
              (isSelected ? AppIcon.selectionFilled : AppIcon.selectionEmpty)
                .image
                .font(.system(size: 24))
                .foregroundColor(isSelected ? .blue : .white)
                .background(
                  Circle()
                    .fill(Color.black.opacity(0.5))
                    .padding(-3)
                )
            }
          )
          .buttonStyle(BorderlessButtonStyle())
          .padding(8)
        }
      }
  }
}
