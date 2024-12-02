// Copyright Justin Bishop, 2024

import SwiftUI

struct OPMLProgressView: View {
  @Environment(\.colorScheme) var colorScheme

  var greenAmount: Int {
    didSet {
      validateAmounts()
    }
  }
  var redAmount: Int {
    didSet {
      validateAmounts()
    }
  }
  private var totalAmount: Int

  init(
    totalAmount: Int,
    greenAmount: Int,
    redAmount: Int
  ) {
    self.totalAmount = totalAmount
    self.greenAmount = greenAmount
    self.redAmount = redAmount
    validateAmounts()
  }

  var body: some View {
    GeometryReader { geometry in
      let totalWidth = geometry.size.width
      let greenWidth = totalWidth * (Double(greenAmount) / Double(totalAmount))
      let redWidth = totalWidth * (Double(redAmount) / Double(totalAmount))
      let remainingWidth = totalWidth - greenWidth - redWidth

      HStack(spacing: 0) {
        Rectangle()
          .fill(Color.green)
          .frame(width: greenWidth)

        Rectangle()
          .fill(Color.red)
          .frame(width: redWidth)

        Rectangle()
          .fill(Color.clear)
          .frame(width: remainingWidth)
      }
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(colorScheme == .dark ? .white : .black, lineWidth: 2)
      )
    }
  }

  private func validateAmounts() {
    if greenAmount + redAmount > totalAmount {
      fatalError("greenAmount + redAmount exceeds totalAmount.")
    }
  }
}

#Preview {
  struct OPMLProgressViewPreview: View {
    @State private var greenAmount: Double = 30
    @State private var redAmount: Double = 50
    @State private var totalAmount: Double = 100

    var body: some View {
      VStack {
        OPMLProgressView(
          totalAmount: Int(totalAmount),
          greenAmount: Int(greenAmount),
          redAmount: Int(redAmount)
        )
        .frame(height: 40)
        .padding()

        Text(
          "Green: \(Int(greenAmount)), Red: \(Int(redAmount))"
        )

        Slider(value: $greenAmount, in: 0...(totalAmount - redAmount), step: 1)
          .padding()
          .accentColor(.green)

        Slider(value: $redAmount, in: 0...(totalAmount - greenAmount), step: 1)
          .padding()
          .accentColor(.red)

        Slider(value: $totalAmount, in: 50...200, step: 1)
          .padding()
          .accentColor(.gray)
      }
    }
  }
  return OPMLProgressViewPreview()
}
