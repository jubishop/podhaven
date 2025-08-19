// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct PodcastHeaderView: View {
  let podcast: any PodcastDisplayable
  let subscribable: Bool
  let subscribed: Bool
  let subscribeAction: (() -> Void)?
  let unsubscribeAction: (() -> Void)?

  init(
    podcast: any PodcastDisplayable,
    subscribable: Bool,
    subscribed: Bool,
    subscribeAction: (() -> Void)?,
    unsubscribeAction: (() -> Void)?
  ) {
    self.podcast = podcast
    self.subscribable = subscribable
    self.subscribed = subscribed
    self.subscribeAction = subscribeAction
    self.unsubscribeAction = unsubscribeAction
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      LazyImage(url: podcast.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
              VStack {
                Image(systemName: "photo")
                  .foregroundColor(.white.opacity(0.8))
                  .font(.title)
                Text("No Image")
                  .font(.caption)
                  .foregroundColor(.white.opacity(0.8))
              }
            )
        }
      }
      .frame(width: 120, height: 120)
      .clipped()
      .cornerRadius(12)
      .shadow(radius: 4)

      VStack(alignment: .leading, spacing: 8) {
        Text(podcast.title)
          .font(.title3)
          .fontWeight(.bold)
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        if let link = podcast.link {
          Link(destination: link) {
            HStack(spacing: 4) {
              Image(systemName: "link")
              Text("Visit Website")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
          }
        }

        if subscribable {
          Button(action: {
            if subscribed {
              unsubscribeAction?()
            } else {
              subscribeAction?()
            }
          }) {
            HStack(spacing: 4) {
              Image(systemName: subscribed ? "minus.circle" : "plus.circle")
              Text(subscribed ? "Unsubscribe" : "Subscribe")
            }
            .font(.caption)
            .foregroundColor(.accentColor)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
