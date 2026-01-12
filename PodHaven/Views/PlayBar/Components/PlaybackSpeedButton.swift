// Copyright Justin Bishop, 2025

import SwiftUI

struct PlaybackSpeedButton: View {
  @Binding var rate: Float
  @Binding var isShowingPopover: Bool

  let containerWidth: CGFloat

  var body: some View {
    Button {
      isShowingPopover = true
    } label: {
      Text("\(formatRate(rate))x")
        .font(.callout)
        .fontWeight(.semibold)
        .fontDesign(.rounded)
    }
    .popover(
      isPresented: $isShowingPopover,
      attachmentAnchor: .point(.trailing),
      arrowEdge: .leading
    ) {
      VStack(spacing: 8) {
        Text("Adjust Playback Speed")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Slider(
          value: $rate,
          in: 0.8...2.0,
          step: 0.1
        ) {
          Text("Playback Speed")
        } minimumValueLabel: {
          Text("0.8x")
            .font(.caption)
            .foregroundStyle(.secondary)
        } maximumValueLabel: {
          Text("2.0x")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding()
      .frame(idealWidth: containerWidth * 2.0 / 3.0)
      .presentationCompactAdaptation(.popover)
    }
  }

  private func formatRate(_ rate: Float) -> String {
    Double(rate).formatted(decimalPlaces: 1)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var rate: Float = 1.0
  @Previewable @State var isShowingPopover = false

  PlaybackSpeedButton(
    rate: $rate,
    isShowingPopover: $isShowingPopover,
    containerWidth: 400
  )
}
#endif
