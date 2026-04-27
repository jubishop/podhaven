// Copyright Justin Bishop, 2026

import SwiftUI

@MainActor @ViewBuilder
func ratingMenuButtons(
  showClear: Bool,
  rate: @escaping @MainActor (EpisodeRating?) -> Void
) -> some View {
  AppIcon.loveEpisode.labelButton {
    rate(.loved)
  }

  AppIcon.likeEpisode.labelButton {
    rate(.liked)
  }

  AppIcon.dislikeEpisode.labelButton {
    rate(.disliked)
  }

  if showClear {
    AppIcon.clearRating.labelButton {
      rate(nil)
    }
  }
}
