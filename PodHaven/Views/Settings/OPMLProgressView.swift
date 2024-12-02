// Copyright Justin Bishop, 2024

import SwiftUI

struct OPMLProgressView: View {
  @Environment(\.colorScheme) var colorScheme

  @Binding var greenAmount: Double {
    didSet {
      validateAmounts()
    }
  }
  @Binding var redAmount: Double {
    didSet {
      validateAmounts()
    }
  }
  private var totalAmount: Double

  init(
    totalAmount: Double,
    greenAmount: Binding<Double>,
    redAmount: Binding<Double>
  ) {
    self.totalAmount = totalAmount
    self._greenAmount = greenAmount
    self._redAmount = redAmount
    validateAmounts()
  }

  var body: some View {
    GeometryReader { geometry in
      let totalWidth = geometry.size.width
      let greenWidth = totalWidth * (greenAmount / totalAmount)
      let redWidth = totalWidth * (redAmount / totalAmount)
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
          totalAmount: totalAmount,
          greenAmount: $greenAmount,
          redAmount: $redAmount
        )
        .frame(height: 40)
        .padding()

        Text(
          "Green: \(greenAmount, specifier: "%.0f"), Red: \(redAmount, specifier: "%.0f")"
        )

        Slider(value: $greenAmount, in: 0...(totalAmount - redAmount))
          .padding()
          .accentColor(.green)

        Slider(value: $redAmount, in: 0...(totalAmount - greenAmount))
          .padding()
          .accentColor(.red)

        Slider(value: $totalAmount, in: 50...200)
          .padding()
          .accentColor(.gray)
      }
    }
  }
  return OPMLProgressViewPreview()
}
