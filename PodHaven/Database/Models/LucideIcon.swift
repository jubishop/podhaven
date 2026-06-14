// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// User-selectable icon assigned to a Tag or SmartList. The rawValue is the
// Lucide icon id, which is also the namespaced asset name under
// Assets.xcassets/LucideIcons. DatabaseValueConvertible bridges the rawValue
// into the tag.icon / smartList.icon columns. The picker presentation metadata
// and SwiftUI rendering live in View-layer extensions so this data-layer type
// stays free of UI dependencies.
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
}
