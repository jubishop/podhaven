// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// User-selectable icon assigned to a Tag or SmartList. The rawValue is the
// Lucide icon id, which is also the namespaced asset name under
// Assets.xcassets/LucideIcons. DatabaseValueConvertible bridges the rawValue
// into the tag.icon / smartList.icon columns. The SwiftUI rendering lives in a
// View-layer extension so this data-layer type stays free of UI dependencies.
enum LucideIcon: String, Codable, DatabaseValueConvertible, CaseIterable, Sendable, Identifiable {
  // News & Society
  case newspaper, globe, vote, landmark, gavel, scale, megaphone, quote
  case messageSquare = "message-square"
  case users, handshake
  case heartHandshake = "heart-handshake"
  case recycle, fingerprint, radio, siren, church

  // Knowledge & Learning
  case graduationCap = "graduation-cap"
  case school
  case bookOpen = "book-open"
  case bookMarked = "book-marked"
  case library, pencil, scroll, brain, lightbulb, atom
  case flaskConical = "flask-conical"
  case dna, microscope, telescope, rocket, languages, calculator, code, puzzle

  // Tech & Business
  case cpu, monitor, smartphone, wifi, server, database, bot, shield, briefcase, presentation
  case trendingUp = "trending-up"
  case banknote
  case creditCard = "credit-card"
  case piggyBank = "piggy-bank"
  case bitcoin
  case building2 = "building-2"
  case factory
  case shoppingBag = "shopping-bag"

  // Entertainment & Arts
  case music, headphones
  case audioLines = "audio-lines"
  case podcast, mic, guitar, disc, film, popcorn, clapperboard, tv, drama
  case gamepad2 = "gamepad-2"
  case dice5 = "dice-5"
  case palette, paintbrush, camera, feather, book, laugh
  case wandSparkles = "wand-sparkles"
  case swords

  // Health & Lifestyle
  case heartPulse = "heart-pulse"
  case stethoscope, pill, dumbbell, footprints, bike, moon, utensils, salad, apple
  case chefHat = "chef-hat"
  case pizza, cake, wine
  case glassWater = "glass-water"
  case coffee, leaf, sprout, flower, shirt

  // Relationships & Self
  case heart, user
  case usersRound = "users-round"
  case baby
  case handHeart = "hand-heart"
  case gift, target, award, smile, crown, gem

  // Sports & Outdoors
  case trophy, medal, goal, volleyball, mountain, tent, compass, anchor, ship, tractor, trees
  case treePine = "tree-pine"
  case bird, fish, rabbit
  case pawPrint = "paw-print"
  case dog, cat

  // Travel & Places
  case plane, luggage
  case treePalm = "tree-palm"
  case hotel
  case mapPin = "map-pin"
  case map, car, fuel, bus
  case trainFront = "train-front"
  case house, building, castle, umbrella

  // Mood & Tone
  case frown, meh, angry
  case heartCrack = "heart-crack"
  case flame, zap
  case partyPopper = "party-popper"
  case rainbow, waves, cloud
  case cloudRain = "cloud-rain"
  case sun, snowflake, ghost, skull

  // Organize & Status
  case star, bookmark, flag, pin, tag, folder, filter
  case listMusic = "list-music"
  case shuffle, play, inbox, sparkles
  case thumbsUp = "thumbs-up"
  case clock, hourglass
  case circleCheck = "circle-check"
  case history, `repeat`, archive, download, bell, calendar, eye, rss

  var id: String { rawValue }

  // Human label shown in the picker; also searchable.
  var label: String { Self.labelsByIcon[self] ?? rawValue }

  // MARK: - Categorization

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
        (.archive, "Archive"), (.download, "Downloaded"), (.bell, "Notifications"),
        (.calendar, "Schedule"), (.eye, "Watched"), (.rss, "Feeds"),
      ]
    ),
  ]

  private static let labelsByIcon: [LucideIcon: String] = Dictionary(
    uniqueKeysWithValues: groups.flatMap { group in group.entries.map { ($0.icon, $0.label) } }
  )
}

extension LucideIcon.Group {
  fileprivate init(_ category: LucideIcon.Category, _ entries: [(LucideIcon, String)]) {
    self.init(
      category: category,
      entries: entries.map { LucideIcon.Entry(icon: $0.0, label: $0.1) }
    )
  }
}
