// Copyright Justin Bishop, 2025

import Charts
import OrderedCollections
import SwiftUI

struct CircularProgressView: View {
  private let totalAmount: Double
  private let colorAmounts: OrderedDictionary<Color, Double>
  private let innerRadius: MarkDimension
  private let angularInset: CGFloat?
  private var totalColorAmount: Double { colorAmounts.values.reduce(0, +) }

  init(
    totalAmount: Double = 1,
    colorAmounts: OrderedDictionary<Color, Double>,
    innerRadius: MarkDimension = .ratio(0.5),
    angularInset: CGFloat? = 2
  ) {
    self.totalAmount = totalAmount
    self.colorAmounts = colorAmounts
    self.innerRadius = innerRadius
    self.angularInset = angularInset
  }

  var body: some View {
    Chart {
      ForEach(Array(colorAmounts.keys), id: \.self) { color in
        let amount = colorAmounts[color] ?? 0
        SectorMark(
          angle: .value("Value", amount),
          innerRadius: innerRadius,
          angularInset: angularInset
        )
        .foregroundStyle(color.gradient)
      }
      if totalAmount > totalColorAmount {
        SectorMark(angle: .value("Value", totalAmount - totalColorAmount))
          .foregroundStyle(.opacity(0))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .aspectRatio(1, contentMode: .fit)
  }
}

#Preview {
  @Previewable @State var greenAmount: Double = 30
  @Previewable @State var redAmount: Double = 50
  @Previewable @State var blueAmount: Double = 10
  @Previewable @State var totalAmount: Double = 100

  VStack {
    CircularProgressView(
      totalAmount: totalAmount,
      colorAmounts: [
        .green: greenAmount, .red: redAmount, .blue: blueAmount,
      ]
    )
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
