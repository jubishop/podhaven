// Copyright Justin Bishop, 2026

import Foundation

// LucideIcon is defined in the data layer; the icon picker's presentation
// metadata (categories, human labels, ordering, search) lives here so Database/
// carries no UI dependency. Only the icon picker reads these.
extension LucideIcon {
  enum Category: String, CaseIterable, Identifiable, Sendable {
    case newsSociety = "News & Society"
    case knowledge = "Knowledge & Learning"
    case techBusiness = "Tech & Business"
    case entertainment = "Entertainment & Arts"
    case healthLifestyle = "Health & Lifestyle"
    case relationshipsSelf = "Relationships & Self"
    case sportsOutdoors = "Sports & Outdoors"
    case travelPlaces = "Travel & Places"
    case moodTone = "Mood & Tone"
    case organizeStatus = "Organize & Status"

    var id: String { rawValue }
  }

  struct Entry: Identifiable, Sendable {
    let icon: LucideIcon
    let label: String
    var id: String { icon.rawValue }
  }

  struct Group: Identifiable, Sendable {
    let category: Category
    let entries: [Entry]
    var id: String { category.rawValue }
  }

  // Source of truth for membership, ordering, and labels. The LucideIconTests
  // suite asserts this covers every case exactly once.
  static let groups: [Group] = [
    Group(
      .newsSociety,
      [
        (.newspaper, "News"), (.globe, "World"), (.vote, "Politics"), (.landmark, "Government"),
        (.gavel, "Law"), (.scale, "Justice"), (.megaphone, "Commentary"), (.quote, "Quotes"),
        (.messageSquare, "Discussion"), (.users, "Society"), (.handshake, "Community"),
        (.heartHandshake, "Charity"), (.recycle, "Environment"), (.fingerprint, "True Crime"),
        (.radio, "Broadcast"), (.siren, "Breaking News"), (.church, "Religion"),
      ]
    ),
    Group(
      .knowledge,
      [
        (.graduationCap, "Education"), (.school, "School"), (.bookOpen, "Books"),
        (.bookMarked, "Reference"), (.library, "Library"), (.pencil, "Study"),
        (.scroll, "History"), (.brain, "Psychology"), (.lightbulb, "Ideas"), (.atom, "Physics"),
        (.flaskConical, "Science"), (.dna, "Biology"), (.microscope, "Research"),
        (.telescope, "Astronomy"), (.rocket, "Space"), (.languages, "Language"),
        (.calculator, "Math"), (.code, "Programming"), (.puzzle, "Trivia"),
      ]
    ),
    Group(
      .techBusiness,
      [
        (.cpu, "Technology"), (.monitor, "Computing"), (.smartphone, "Mobile"),
        (.wifi, "Internet"), (.server, "Cloud"), (.database, "Data"), (.bot, "AI"),
        (.shield, "Security"), (.briefcase, "Business"), (.presentation, "Business Talks"),
        (.trendingUp, "Markets"), (.banknote, "Money"), (.creditCard, "Payments"),
        (.piggyBank, "Saving"), (.bitcoin, "Crypto"), (.building2, "Startups"),
        (.factory, "Industry"), (.shoppingBag, "Shopping"),
      ]
    ),
    Group(
      .entertainment,
      [
        (.music, "Music"), (.headphones, "Audio"), (.audioLines, "Sound"), (.podcast, "Podcasts"),
        (.mic, "Interview"), (.guitar, "Live Music"), (.disc, "DJ & Records"), (.film, "Movies"),
        (.popcorn, "Movie Night"), (.clapperboard, "Film & TV"), (.tv, "Television"),
        (.drama, "Theater"), (.gamepad2, "Gaming"), (.dice5, "Tabletop"), (.palette, "Art"),
        (.paintbrush, "Design"), (.camera, "Photography"), (.feather, "Writing"),
        (.book, "Audiobooks"), (.laugh, "Comedy"), (.wandSparkles, "Fantasy"), (.swords, "Action"),
      ]
    ),
    Group(
      .healthLifestyle,
      [
        (.heartPulse, "Wellness"), (.stethoscope, "Medical"), (.pill, "Medicine"),
        (.dumbbell, "Fitness"), (.footprints, "Running"), (.bike, "Cycling"), (.moon, "Sleep"),
        (.utensils, "Food"), (.salad, "Healthy Eating"), (.apple, "Nutrition"),
        (.chefHat, "Cooking"), (.pizza, "Snacks"), (.cake, "Baking"), (.wine, "Drinks"),
        (.glassWater, "Hydration"), (.coffee, "Coffee"), (.leaf, "Eco"), (.sprout, "Growth"),
        (.flower, "Garden"), (.shirt, "Fashion"),
      ]
    ),
    Group(
      .relationshipsSelf,
      [
        (.heart, "Love"), (.user, "Personal"), (.usersRound, "Family"), (.baby, "Parenting"),
        (.handHeart, "Kindness"), (.gift, "Gifts"), (.target, "Goals"), (.award, "Achievement"),
        (.smile, "Positivity"), (.crown, "Confidence"), (.gem, "Value"),
      ]
    ),
    Group(
      .sportsOutdoors,
      [
        (.trophy, "Sports"), (.medal, "Competition"), (.goal, "Soccer"),
        (.volleyball, "Ball Sports"), (.mountain, "Hiking"), (.tent, "Camping"),
        (.compass, "Adventure"), (.anchor, "Sailing"), (.ship, "Boating"), (.tractor, "Farming"),
        (.trees, "Nature"), (.treePine, "Forest"), (.bird, "Birding"), (.fish, "Fishing"),
        (.rabbit, "Wildlife"), (.pawPrint, "Animals"), (.dog, "Dogs"), (.cat, "Cats"),
      ]
    ),
    Group(
      .travelPlaces,
      [
        (.plane, "Travel"), (.luggage, "Trips"), (.treePalm, "Vacation"), (.hotel, "Hotels"),
        (.mapPin, "Places"), (.map, "Geography"), (.car, "Driving"), (.fuel, "Road Trip"),
        (.bus, "Transit"), (.trainFront, "Trains"), (.house, "Home"), (.building, "City"),
        (.castle, "Landmarks"), (.umbrella, "Beach"),
      ]
    ),
    Group(
      .moodTone,
      [
        (.frown, "Sad"), (.meh, "Meh"), (.angry, "Hot Takes"), (.heartCrack, "Heartbreak"),
        (.flame, "Intense"), (.zap, "Energetic"), (.partyPopper, "Fun"), (.rainbow, "Hopeful"),
        (.waves, "Calm"), (.cloud, "Mellow"), (.cloudRain, "Gloomy"), (.sun, "Upbeat"),
        (.snowflake, "Cool"), (.ghost, "Spooky"), (.skull, "Horror"),
      ]
    ),
    Group(
      .organizeStatus,
      [
        (.star, "Favorites"), (.bookmark, "Saved"), (.flag, "Priority"), (.pin, "Pinned"),
        (.tag, "Tags"), (.folder, "Collections"), (.filter, "Filtered"), (.listMusic, "Playlist"),
        (.shuffle, "Shuffle"), (.play, "Now Playing"), (.inbox, "Inbox"), (.sparkles, "New"),
        (.thumbsUp, "Recommended"), (.clock, "Listen Later"), (.hourglass, "In Progress"),
        (.circleCheck, "Finished"), (.history, "Recently Played"), (.repeat, "Recurring"),
        (.infinity, "Evergreen"), (.archive, "Archive"), (.download, "Downloaded"),
        (.bell, "Notifications"), (.calendar, "Schedule"), (.calendarDays, "Dates"),
        (.calendarRange, "Date Range"), (.eye, "Watched"), (.rss, "Feeds"),
        (.circleX, "Skipped"), (.arrowUpToLine, "To Top"), (.arrowDownToLine, "To Bottom"),
      ]
    ),
  ]
}

extension LucideIcon.Group {
  fileprivate init(_ category: LucideIcon.Category, _ entries: [(LucideIcon, String)]) {
    self.init(
      category: category,
      entries: entries.map { LucideIcon.Entry(icon: $0.0, label: $0.1) }
    )
  }
}
