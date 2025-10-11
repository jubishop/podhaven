// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct EpisodeDetailView: View {
  @DynamicInjected(\.alert) private var alert

  private let viewModel: EpisodeDetailViewModel

  init(viewModel: EpisodeDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .center, spacing: 16) {
          SquareImage(
            image: viewModel.episode.image,
            cornerRadius: 12,
            size: 200
          )
          .shadow(radius: 4)

          VStack(spacing: 8) {
            Text(viewModel.episode.title)
              .font(.title2)
              .fontWeight(.semibold)
              .multilineTextAlignment(.center)

            Button(action: {
              viewModel.showPodcast()
            }) {
              Text(viewModel.episode.podcastTitle)
                .font(.headline)
                .foregroundColor(.accentColor)
                .multilineTextAlignment(.center)
                .underline()
            }
            .buttonStyle(PlainButtonStyle())
          }
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 16) {
          HStack {
            HStack(spacing: 8) {
              AppIcon.publishDate.image
              Text("Published")
                .font(.caption)
                .foregroundColor(.secondary)
              Text(viewModel.episode.pubDate.usShortWithTime)
                .font(.subheadline)
            }

            Spacer()

            if viewModel.episode.cacheStatus == .cached {
              VStack(spacing: 4) {
                AppIcon.episodeCached.image
                Text("Cached")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }

            Spacer()

            HStack(spacing: 8) {
              AppIcon.duration.image
              Text("Duration")
                .font(.caption)
                .foregroundColor(.secondary)
              Text(viewModel.episode.duration.shortDescription)
                .font(.subheadline)
            }
          }
          .padding(.horizontal)

          if let description = viewModel.episode.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("Description")
                .font(.headline)
                .padding(.horizontal)

              HTMLText(description)
                .padding(.horizontal)
            }
          }

          if !viewModel.onDeck {
            VStack(spacing: 12) {
              Button(action: viewModel.playNow) {
                HStack {
                  AppIcon.playNow.image
                  Text(AppIcon.playNow.text)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.primary)
                .cornerRadius(10)
              }

              HStack(spacing: 12) {
                Button(action: viewModel.addToTopOfQueue) {
                  HStack {
                    AppIcon.queueLatestToTop.image
                    Text(viewModel.atTopOfQueue ? "Already at Top" : AppIcon.addToTop.text)
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .cornerRadius(10)
                }
                .disabled(viewModel.atTopOfQueue)

                Button(action: viewModel.appendToQueue) {
                  HStack {
                    AppIcon.queueLatestToBottom.image
                    Text(
                      viewModel.atBottomOfQueue ? "Already at Bottom" : AppIcon.addToBottom.text
                    )
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .cornerRadius(10)
                }
                .disabled(viewModel.atBottomOfQueue)
              }

              let cacheStatus = viewModel.episode.cacheStatus
              if cacheStatus != .cached {
                Button(action: viewModel.cacheEpisode) {
                  HStack {
                    if cacheStatus == .caching {
                      ProgressView()
                        .scaleEffect(0.8)
                      Text("Caching in Progress")
                    } else {
                      AppIcon.cacheEpisode.image
                      Text(AppIcon.cacheEpisode.text)
                    }
                  }
                  .frame(maxWidth: .infinity)
                  .padding()
                  .background(
                    cacheStatus == .caching ? Color.orange.opacity(0.1) : Color.green.opacity(0.1)
                  )
                  .foregroundColor(cacheStatus == .caching ? .orange : .green)
                  .cornerRadius(10)
                }
                .disabled(cacheStatus == .caching)
              }
            }
            .padding(.horizontal)
          }
        }
      }
      .padding(.vertical)
    }
    .task { await viewModel.execute() }
    .onDisappear { viewModel.disappear() }
  }
}
