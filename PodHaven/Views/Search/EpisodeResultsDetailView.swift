// Copyright Justin Bishop, 2025

import FactoryKit
import NukeUI
import SwiftUI

struct EpisodeResultsDetailView: View {
  @DynamicInjected(\.alert) private var alert

  private let viewModel: EpisodeResultsDetailViewModel

  init(viewModel: EpisodeResultsDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .center, spacing: 16) {
          LazyImage(url: viewModel.unsavedPodcastEpisode.image) { state in
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
          .frame(width: 200, height: 200)
          .clipped()
          .cornerRadius(12)
          .shadow(radius: 4)

          VStack(spacing: 8) {
            Text(viewModel.unsavedPodcastEpisode.unsavedEpisode.title)
              .font(.title2)
              .fontWeight(.semibold)
              .multilineTextAlignment(.center)

            Text(viewModel.unsavedPodcastEpisode.unsavedPodcast.title)
              .font(.headline)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 16) {
          HStack {
            HStack(spacing: 8) {
              Image(systemName: "calendar")
                .foregroundColor(.secondary)
              Text("Published")
                .font(.caption)
                .foregroundColor(.secondary)
              Text(viewModel.unsavedPodcastEpisode.unsavedEpisode.pubDate.usShortWithTime)
                .font(.subheadline)
            }

            Spacer()

            if viewModel.unsavedPodcastEpisode.unsavedEpisode.cachedFilename != nil {
              VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                  .foregroundColor(.green)
                Text("Cached")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }

            Spacer()

            HStack(spacing: 8) {
              Image(systemName: "clock")
                .foregroundColor(.secondary)
              Text("Duration")
                .font(.caption)
                .foregroundColor(.secondary)
              Text(viewModel.unsavedPodcastEpisode.unsavedEpisode.duration.shortDescription)
                .font(.subheadline)
            }
          }
          .padding(.horizontal)

          if let description = viewModel.unsavedPodcastEpisode.unsavedEpisode.description,
            !description.isEmpty
          {
            VStack(alignment: .leading, spacing: 8) {
              Text("Description")
                .font(.headline)
                .padding(.horizontal)

              HTMLText(description)
                .font(.body)
                .padding(.horizontal)
            }
          }

          if !viewModel.onDeck {
            VStack(spacing: 12) {
              Button(action: viewModel.playNow) {
                HStack {
                  Image(systemName: "play.fill")
                  Text("Play Now")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
              }

              HStack(spacing: 12) {
                Button(action: viewModel.addToTopOfQueue) {
                  HStack {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    Text(viewModel.atTopOfQueue ? "Already at Top" : "Add to Top")
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .cornerRadius(10)
                }
                .disabled(viewModel.atTopOfQueue)

                Button(action: viewModel.appendToQueue) {
                  HStack {
                    Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    Text(viewModel.atBottomOfQueue ? "Already at Bottom" : "Add to Bottom")
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .cornerRadius(10)
                }
                .disabled(viewModel.atBottomOfQueue)
              }
            }
            .padding(.horizontal)
          }
        }
      }
      .padding(.vertical)
    }
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var unsavedEpisodes: [UnsavedEpisode]?
  @Previewable @State var unsavedPodcast: UnsavedPodcast?

  NavigationStack {
    if let unsavedPodcast = unsavedPodcast, let unsavedEpisodes = unsavedEpisodes {
      EpisodeResultsDetailView(
        viewModel: EpisodeResultsDetailViewModel(
          searchedPodcastEpisode: SearchedPodcastEpisode(
            searchedText: "Bill Maher",
            unsavedPodcastEpisode: UnsavedPodcastEpisode(
              unsavedPodcast: unsavedPodcast,
              unsavedEpisode: unsavedEpisodes.randomElement()!
            )
          )
        )
      )
    }
  }
  .preview()
  .task {
    (unsavedPodcast, unsavedEpisodes) = try! await PreviewHelpers.loadUnsavedPodcastEpisodes()
  }
}
#endif
