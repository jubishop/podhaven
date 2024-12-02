// Copyright Justin Bishop, 2024

import OrderedCollections
import SwiftUI

struct ProgressView: View {
  private let totalAmount: Double
  private let colorAmounts: OrderedDictionary<Color, Double>
  private var totalColorAmount: Double {
    colorAmounts.values.reduce(0, +)
  }
  init(
    totalAmount: Double = 100,
    colorAmounts: OrderedDictionary<Color, Double>
  ) {
    self.totalAmount = totalAmount
    self.colorAmounts = colorAmounts
  }

  var body: some View {
    GeometryReader { geometry in
      let totalWidth = geometry.size.width
      let rectangle = RoundedRectangle(cornerRadius: geometry.size.height / 3)
      let calculatedColorAmounts =
        totalColorAmount > totalAmount
        ? colorAmounts.mapValues { $0 * totalAmount / totalColorAmount }
        : colorAmounts
      let colorWidths = calculatedColorAmounts.mapValues {
        totalWidth * $0 / totalAmount
      }
      let remainingWidth = totalWidth - colorWidths.values.reduce(0, +)

      HStack(spacing: 0) {
        ForEach(Array(colorWidths.keys), id: \.self) { color in
          if let width = colorWidths[color] {
            Rectangle()
              .fill(color)
              .frame(width: width)
          }
        }
        Rectangle()
          .fill(Color.clear)
          .frame(width: remainingWidth)
      }
      .clipShape(rectangle)
      .overlay(rectangle.stroke(.primary, lineWidth: 2))
    }
  }
}

#Preview {
  struct ProgressViewPreview: View {
    @State private var greenAmount: Double = 30
    @State private var redAmount: Double = 50
    @State private var blueAmount: Double = 10
    @State private var totalAmount: Double = 100

    var body: some View {
      VStack {
        ProgressView(
          totalAmount: totalAmount,
          colorAmounts: [
            .green: greenAmount, .red: redAmount, .blue: blueAmount,
          ]
        )
        .frame(height: 40)
        .padding()

        Text(
          """
          Green: \(Int(greenAmount)), \
          Red: \(Int(redAmount)), \
          Blue: \(Int(blueAmount))
          """
        )

        Slider(value: $greenAmount, in: 0...totalAmount)
          .padding()
          .accentColor(.green)

        Slider(value: $redAmount, in: 0...totalAmount)
          .padding()
          .accentColor(.red)

        Slider(value: $blueAmount, in: 0...totalAmount)
          .padding()
          .accentColor(.blue)

        Slider(value: $totalAmount, in: 50...200)
          .padding()
          .accentColor(.gray)
      }
    }
  }
  return ProgressViewPreview()
}
