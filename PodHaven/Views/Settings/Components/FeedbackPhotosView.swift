// Copyright Justin Bishop, 2026

import SwiftUI

struct FeedbackPhotosView: View {
  let photos: [Data]

  var body: some View {
    if !photos.isEmpty {
      ScrollView(.horizontal) {
        HStack(spacing: 12) {
          ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
            if let uiImage = UIImage(data: data) {
              Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Attached photo \(index + 1)")
                .accessibilityValue("\(index + 1) of \(photos.count)")
            }
          }
        }
      }
    }
  }
}

#if DEBUG
#Preview("One portrait photo") {
  FeedbackPhotosPreview(sizes: [CGSize(width: 100, height: 200)])
}

#Preview("Two photos that fit") {
  FeedbackPhotosPreview(sizes: Array(repeating: CGSize(width: 100, height: 200), count: 2))
}

#Preview("Overflow with landscape photos") {
  FeedbackPhotosPreview(sizes: [
    CGSize(width: 100, height: 200),
    CGSize(width: 300, height: 200),
    CGSize(width: 100, height: 200),
    CGSize(width: 200, height: 100),
    CGSize(width: 100, height: 200),
  ])
}

#Preview("Overflow at largest Dynamic Type") {
  FeedbackPhotosPreview(sizes: Array(repeating: CGSize(width: 100, height: 200), count: 5))
    .dynamicTypeSize(.accessibility5)
}

private struct FeedbackPhotosPreview: View {
  let sizes: [CGSize]

  var body: some View {
    Form {
      Section("Photos") {
        FeedbackPhotosView(
          photos: sizes.enumerated()
            .compactMap { index, size in
              UIGraphicsImageRenderer(size: size)
                .image { context in
                  UIColor.secondarySystemBackground.setFill()
                  context.fill(CGRect(origin: .zero, size: size))
                  UIColor.systemBlue.setFill()
                  context.fill(CGRect(x: 8, y: 8, width: size.width - 16, height: 36))
                  NSString(string: "Photo \(index + 1)")
                    .draw(
                      at: CGPoint(x: 8, y: 56),
                      withAttributes: [
                        .font: UIFont.systemFont(ofSize: 16),
                        .foregroundColor: UIColor.label,
                      ]
                    )
                }
                .pngData()
            }
        )
      }
    }
  }
}
#endif
