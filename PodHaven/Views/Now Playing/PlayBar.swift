// Copyright Justin Bishop, 2024

import AVFoundation
import SwiftUI

struct PlayBar: View {
  @State private var isPlaying = false

  var body: some View {
    VStack {
      Text("Audio Player")
        .font(.title)
        .padding()

//      Slider(value: $playBackManager.progress, in: 0...1) {
//        Text("Progress")
//      } minimumValueLabel: {
//        Text("0:00")
//      } maximumValueLabel: {
//        Text(playBackManager.durationText)
//      }
//      .padding()
//
//      HStack {
//        Button(action: {
//          playBackManager.seekBackward()
//        }) {
//          Image(systemName: "gobackward.10")
//        }
//        .padding()
//
//        Button(action: {
//          if isPlaying {
//            playBackManager.pause()
//          } else {
//            playBackManager.play()
//          }
//          isPlaying.toggle()
//        }) {
//          Image(systemName: isPlaying ? "pause.circle" : "play.circle")
//            .font(.largeTitle)
//        }
//        .padding()
//
//        Button(action: {
//          playBackManager.seekForward()
//        }) {
//          Image(systemName: "goforward.10")
//        }
//        .padding()
//      }
//    }
//    .onDisappear {
//      playBackManager.stop()
    }
  }
}

#Preview {
  PlayBar()
}
