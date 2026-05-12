# Embedding Model Alternatives

Survey of replacements for `NLContextualEmbedding` in the recommendation engine. Researched 2026-05-11 after shipping the corpus-mean whitening fix that worked around `NLContextualEmbedding`'s narrow-cone anisotropy.

## Status

Holding. Whitening + 2× cadence half-life is live. No migration planned before WWDC '26 — Apple has historically dropped surprise text APIs at WWDC and the right next step (a new `FoundationModels`-derived embedding API) would moot the work below. Re-evaluate after the keynote.

## Why this doc exists

`NLContextualEmbedding` is BERT-family and exhibits the well-documented anisotropy that all masked-language-model embeddings have: vectors collapse into a narrow cone around the corpus mean, raw cosine similarities sit in `~[0.85, 0.99]` regardless of semantic relevance, and the `(sim + 2) / 4` remap in `RecommendationEngine.scoreCandidate` squashes everything to `~[0.50, 0.55]`. We patched that with corpus-mean centering (see `RecommendationEngine.whiten(_:mean:)`), but whitening is *working around* a model property that newer architectures don't have. This doc tracks what a real swap would look like.

## Hard constraints

Anything we'd consider has to be:

- **On-device.** No paid API, no server we have to run.
- **Free for the user.** Bundled in the app, no per-user costs.
- **Privacy-preserving.** No phoning out with the user's library.

Those constraints kill cloud embeddings (OpenAI, Voyage, Cohere, Gemini) and any hybrid that requires us to stand up an embedding pipeline server-side. Both are technically attractive — Voyage 3-large beats every open model on retrieval benchmarks, and a server-side precompute mirrors how Spotify/Apple Music do it — but they're out of scope here.

## What Apple actually ships (iOS 26)

| API | suitable? | why |
|---|---|---|
| `NLContextualEmbedding` | current baseline | BERT-family, anisotropic; whitening helps |
| `NLEmbedding` (word + sentence) | no | older architecture (predates `NLContextualEmbedding` by several iOS versions), same cone problem, less expressive |
| `FoundationModels` | not yet | iOS 26's 3B on-device LLM is generation-only; no public embedding API or hidden-state hook. WWDC '26 is the realistic moment for this to change |
| `VNGenerateImageFeaturePrintRequest` | wrong modality | image embeddings only |
| Core ML / Create ML | runtime, not a model | gives us the *means* to run a converted model, not a better model itself |

So Apple-native is `NLContextualEmbedding` and nothing else worth migrating to today.

## Realistic upgrade: CoreML-converted Sentence-BERT

The other family worth considering is **contrastive-trained sentence embeddings** — models trained explicitly on `(similar, dissimilar)` pairs whose vectors are near-isotropic by construction. Convert one to Core ML, bundle the `.mlpackage`, run on the Neural Engine.

Practical candidates as of 2026-05:

| model | dims | bundle (fp16) | MTEB retrieval | notes |
|---|---|---|---|---|
| `all-MiniLM-L6-v2` | 384 | ~22 MB | ~42 | Community CoreML port + Swift tokenizer + SwiftUI demo already exists |
| `BGE-small-en-v1.5` | 384 | ~33 MB | ~52 | Better quality, similar size |
| `gte-small` | 384 | ~33 MB | ~50 | Comparable to BGE |
| `BGE-base-en-v1.5` | 768 | ~110 MB | ~55 | Real quality jump; bundle size becomes a concern |
| `Qwen3-Embedding-0.6B` | up to 1024 | ~600 MB | ~64 | 2026 leader at small scale; brutal bundle size for an iOS app |

Realistic first move would be MiniLM-L6 as a proof-point — smallest bundle, existing port — followed by sizing up to BGE-small or BGE-base if discrimination is good but we want more headroom.

## Tradeoffs vs current

Pros of swapping to CoreML-Sentence-BERT:

- Drop the whitening hack. Raw cosine actually means something.
- Discrimination across the user's library improves substantially. The hard problem isn't "which Gastropod episode" — it's "is this AI podcast more like Hard Fork or like a generic news show," and contrastive models are several × better at that than `NLContextualEmbedding` even after whitening.
- Runs on the Neural Engine via Core ML — comparable per-episode latency to the current setup.

Costs:

- **Bundle size.** 22 MB for MiniLM, 110 MB for BGE-base. Worth checking the current `.ipa` size and App Thinning per-device download limits before picking the bigger model.
- **Tokenizer.** Sentence-BERT models use WordPiece/SentencePiece, not Apple's tokenizer. Need to ship Swift tokenizer code (the HF community ports include it).
- **Re-embedding.** Bumping `EmbeddingService.recipeVersion` triggers re-embedding all ~94k episodes. With NLContextualEmbedding that's minutes; with a CoreML transformer probably 10–30 min of background work depending on Neural Engine throughput. Background-task friendly, but worth measuring before committing.
- **Whitening machinery stays.** Sentence-BERT vectors are *near*-isotropic, not perfectly. The cached-mean whitening in `RecommendationEngine.currentWhiteningMean` keeps helping at the margin, and a `recipeVersion` bump auto-invalidates the cached mean against the new model.

## Why we wait for WWDC

`FoundationModels` introduced the on-device 3B-parameter LLM in iOS 26 with no embedding surface. The natural next step — and one with precedent in how Apple has evolved similar APIs — is to expose either an embedding API derived from the same model or a separate `NLContextualEmbedding`-replacement built on the new model family. If that ships at WWDC '26, it likely:

- Solves the cone problem (newer training regimes; potentially contrastive-tuned).
- Eliminates the bundle-size concern (model lives in the OS, not the app).
- Eliminates the tokenizer integration burden.
- Likely keeps the Apple-Intelligence-eligible-device gate (older hardware would still need a fallback path — `NLContextualEmbedding` + whitening).

The downside risk of waiting is low: the current behavior is decent post-whitening, and the work below is the same shape regardless of whether we end up using a Sentence-BERT port or an Apple-provided successor.

## Decision

Re-evaluate after WWDC '26 (June 2026). Two outcomes:

1. **Apple ships a usable text-embedding API on `FoundationModels` (or successor).** Migrate to that. The `EmbeddingService` is already abstracted behind `Embeddable` / `ContextualEmbedding` and a `recipeVersion` bump handles re-embedding. Roughly a week of integration work plus the background-task wait for re-embedding to complete on each user's device.

2. **WWDC ships nothing relevant.** Pick a CoreML-converted Sentence-BERT model — start with MiniLM-L6 to validate, size up to BGE-small or BGE-base if discrimination justifies the bundle. ~1–2 weeks of integration: Core ML packaging, tokenizer port, plumbing through `Embeddable`, recipe-version bump, validation pass against the whitened-NLContextualEmbedding baseline.

Either way, no work happens before WWDC.

## Sources

- [Ethayarajh, "How contextual are contextualized word representations?"](https://kawine.github.io/blog/nlp/2020/02/03/contextual.html) — original BERT/ELMo/GPT-2 anisotropy analysis
- [Apple Foundation Models framework](https://developer.apple.com/documentation/FoundationModels) — confirmed: no public embedding API in iOS 26
- [`sentence-transformers/all-MiniLM-L6-v2` — CoreML port discussion](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/discussions/29)
- [`huggingface/swift-coreml-transformers`](https://github.com/huggingface/swift-coreml-transformers) — Swift package for Core ML transformer integration
- [MTEB leaderboard snapshot, March 2026](https://awesomeagents.ai/leaderboards/embedding-model-leaderboard-mteb-march-2026/)
- [Voyage 3-large announcement](https://blog.voyageai.com/2025/01/07/voyage-3-large/) — for the cloud-option benchmarks we ruled out
- [OpenAI text-embedding-3 announcement](https://openai.com/index/new-embedding-models-and-api-updates/) — same
