// Copyright Justin Bishop, 2024

import SwiftUI

struct PlayBar: View {
  @Binding var fullStackHeight: CGFloat
  @Binding var internalTabHeight: CGFloat

  init(fullStackHeight: Binding<CGFloat>, internalTabHeight: Binding<CGFloat>) {
    _fullStackHeight = fullStackHeight
    _internalTabHeight = internalTabHeight
  }

  var body: some View {
    HStack {
      Button(action: {
        print("Previous button tapped")
      }) {
        Image(systemName: "backward.fill")
          .font(.title)
          .foregroundColor(.white)
      }

      Spacer()

      Button(action: {
        print("Play button tapped")
      }) {
        Image(systemName: "play.fill")
          .font(.title)
          .foregroundColor(.white)
      }

      Spacer()

      Button(action: {
        print("Next button tapped")
      }) {
        Image(systemName: "forward.fill")
          .font(.title)
          .foregroundColor(.white)
      }
    }
    .padding()
    .background(Capsule().fill(Color.blue))
    .padding(.horizontal)
    .offset(y: internalTabHeight - fullStackHeight)
  }
}

#Preview {
  PlayBar(fullStackHeight: .constant(600), internalTabHeight: .constant(800))
}
