# Podcast API Research - Guest Search Capabilities

**Date:** 2025-10-27
**Context:** Investigating alternatives to iTunes Search API for better guest/person search functionality

---

## Problem Statement

The iTunes Search API lacks dedicated guest search capabilities. It only searches:
- Podcast titles
- Artist/author names
- General descriptions

This limits our ability to help users find podcasts featuring specific guests.

---

## API Comparison

### 1. Podcast Index API ⭐ **RECOMMENDED**

**Website:** https://podcastindex.org
**Docs:** https://podcastindex-org.github.io/docs-api/
**Signup:** https://api.podcastindex.org

#### Pros
- ✅ **Free forever** - designed to preserve the open podcasting ecosystem
- ✅ **Dedicated `searchEpisodesByPerson` endpoint** - specifically for finding episodes by guest/person
- ✅ **Open source** and community-driven
- ✅ **No usage limits** on free tier
- ✅ **Comprehensive** podcast/episode metadata
- ✅ **Aligns with independent podcasting ethos**

#### Cons
- ⚠️ Less polished documentation than commercial alternatives
- ⚠️ Smaller dataset than Listen Notes (but still comprehensive)

#### Key Features
- `searchEpisodesByPerson(q, fullText)` - search episodes by person/guest
- Search by feed URL, feed ID, iTunes ID, GUID
- Advanced category listings
- Episode-level metadata

#### Pricing
**FREE** - No cost, forever

---

### 2. Podchaser API (Best Guest Database)

**Website:** https://www.podchaser.com
**API Docs:** https://api-docs.podchaser.com
**Features:** https://features.podchaser.com/api/

#### Pros
- ✅ **17+ million creator and guest credits** - most comprehensive guest database
- ✅ **Only API with dedicated guest appearance tracking**
- ✅ Advanced filtering by guest, host, creator
- ✅ Rich metadata: guest industries, typical profiles, appearance purposes
- ✅ Directory search specifically for host/creator/guest credits

#### Cons
- ⚠️ Free tier: 25,000 API points/month (limited)
- ⚠️ Paid tiers require custom quotes (no transparent pricing)
- ⚠️ Commercial focus

#### Key Features
- Over 17 million creator and guest credits
- Search by genre, keyword, guest, or creator
- Podcast metadata, ratings, reviews
- Demographic information

#### Pricing
- **Free tier:** 25,000 points/month, essential data fields
- **Paid tiers:** Custom pricing (contact sales)

---

### 3. Listen Notes API (Most Popular)

**Website:** https://www.listennotes.com/api
**Docs:** https://www.listennotes.com/api/docs/

#### Pros
- ✅ **Largest dataset:** 3.6M podcasts, 185M+ episodes
- ✅ **Full-text search** across show notes and transcripts
- ✅ Can search by "people, places, or topics"
- ✅ **Mature API** with excellent documentation
- ✅ Typeahead/autocomplete support
- ✅ Trusted by 10,775+ companies since 2017

#### Cons
- ⚠️ **Free tier:** only 30 results per query
- ⚠️ **Pro tier:** ~$49-200/month range
- ⚠️ No dedicated guest search (uses general text search)

#### Key Features
- Full-text search of metadata for all podcasts/episodes
- Search show notes and transcripts by people, places, topics
- Recommendations for podcasts & episodes
- Best podcasts by category
- Playlist management

#### Pricing
- **FREE:** Up to 30 results per query
- **PRO:** Up to 300 results per query (~$49-200/month estimated)
- **ENTERPRISE:** Up to 10,000 results per query (custom pricing)

---

### 4. Taddy API (AI-Powered)

**Website:** https://taddy.org/developers/podcast-api

#### Pros
- ✅ **Automatic person extraction** with roles (Host, Guest, etc.)
- ✅ **Blazing fast full-text search** on all podcasts and episodes
- ✅ Structured data extraction from conversations

#### Cons
- ⚠️ **$100/month minimum**
- ⚠️ Newer/less proven than alternatives

#### Key Features
- "Person" data listing with roles
- Full-text search capabilities
- AI-powered metadata extraction

#### Pricing
**$100/month** for thousands of podcast searches

---

### 5. Rephonic API (Transcript-Based)

**Website:** https://rephonic.com/developers

#### Pros
- ✅ **Automatically extracts guests from episode transcripts**
- ✅ Guest metadata: industry, affiliation, appearance purpose
- ✅ Recent guests tracking
- ✅ Typical guest profiles

#### Cons
- ⚠️ Limited information available
- ⚠️ Pricing unclear

#### Key Features
- Returns host and guest information
- Guest profiles with industry and purpose
- Extracted from episode transcripts

#### Pricing
**Unknown** - contact for pricing

---

### 6. Pod Engine API (Comprehensive Intelligence)

**Website:** https://www.podengine.ai/solutions/podcast-api

#### Pros
- ✅ Automatically extracts people, companies, products, topics
- ✅ Converts unstructured conversations into structured data
- ✅ First MCP server integration (2025)

#### Cons
- ⚠️ **$100/month**
- ⚠️ May be overkill for simple guest search

#### Pricing
**$100/month** for thousands of searches

---

## Recommendation

### Primary Choice: **Podcast Index API**

**Rationale:**
1. **Free forever** - no cost concerns for initial implementation
2. **Dedicated guest search** - `searchEpisodesByPerson` endpoint specifically built for this use case
3. **Open source ethos** - aligns with independent podcasting values
4. **No usage limits** - can scale freely without tier restrictions
5. **Good enough dataset** - comprehensive coverage for most use cases

### Secondary Choice: **Podchaser API**

**When to use:**
- Need the most comprehensive guest credits (17M+)
- Want richer guest metadata (industries, roles, typical profiles)
- 25K points/month free tier is sufficient for our usage

**When to upgrade:**
- User base grows and needs exceed free tier
- Guest search becomes a premium feature we can monetize

---

## Implementation Considerations

### Podcast Index API Integration

**Required:**
- API key and secret from https://api.podcastindex.org
- Implement authentication (similar to current `ITunesService`)
- Create new `PodcastIndexService` conforming to `DataFetchable`

**Key Endpoints:**
```
GET /api/1.0/search/byPerson
  - q: person name
  - fullText: boolean (search full episode text or just titles)
  - max: max results
```

**Architecture:**
- Add to `iTunes/` directory or create new `PodcastIndex/` directory
- Factory registration in `Container` extensions
- Integrate with existing `SearchViewModel` for guest search tab/filter

### Data Model Considerations

**Current models (iTunes):**
- `ITunesSearchResult`
- `ITunesPodcast`

**New models needed:**
- `PodcastIndexEpisodeResult` - episodes with person mentions
- `PodcastIndexPerson` - person metadata
- May need to enhance `Episode` model to include guest/person credits

### Migration Strategy

**Phase 1:** Add Podcast Index alongside iTunes
- Keep iTunes for podcast discovery/trending
- Add Podcast Index for guest-specific searches
- New "Search by Guest" feature in search tab

**Phase 2:** Evaluate and consolidate (optional)
- Analyze usage patterns
- Consider replacing iTunes entirely if Podcast Index covers all needs
- Or maintain both for different use cases

---

## Next Steps

1. ✅ Research completed
2. ⬜ Create free Podcast Index API account
3. ⬜ Implement `PodcastIndexService`
4. ⬜ Create models for Podcast Index responses
5. ⬜ Add guest search UI to `SearchViewModel`
6. ⬜ Test with common guest names
7. ⬜ Consider Podchaser as future enhancement

---

## Additional Resources

- **Podcast Index GitHub:** https://github.com/Podcastindex-org
- **Podcast Index Community:** Active open source community
- **Listen Notes Comparison:** https://www.podchaser.com/articles/api/podchaser-api-vs-listen-notes-api
- **PodcastIndex vs Taddy:** https://taddy.org/blog/podcastindex-vs-taddy-podcast-api
