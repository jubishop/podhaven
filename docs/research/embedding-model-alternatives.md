---
status: blocked
---

# Embedding Model Alternatives

Survey of replacements for `NLContextualEmbedding` in the recommendation engine. Researched 2026-05-11 after shipping the corpus-mean whitening fix that worked around `NLContextualEmbedding`'s narrow-cone anisotropy.

## Status

Whitening + 2× cadence half-life shipped, then upgraded to **mean centering + top-3 principal-component removal** ("variant E3" / Mu et al.'s "All-but-the-top") after Python experiments showed it produces meaningfully better topical clustering than the centering-only baseline. No migration to a different embedding model planned before WWDC '26 — Apple has historically dropped surprise text APIs at WWDC and the right next step (a new `FoundationModels`-derived embedding API) would moot the migration work. Re-evaluate after the keynote.

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

So Apple-native is `NLContextualEmbedding` and nothing else worth migrating to today. The two real options to look at are (a) better post-processing of NLContextualEmbedding vectors (covered below in "Post-processing experiments") and (b) swapping to a contrastive-trained Sentence-BERT model via Core ML (covered in "Future directions").

## Post-processing experiments (run against my own DB, 2026-05-11)

Two rounds of Python simulation against a snapshot of my real `episodeEmbedding` table (~94k embeddings, 27 rated signals, 25 partial-listen signals). All variants share the same scoring (centroids, affinity, freshness, 2× cadence half-life). Only the embedding post-processing differs.

### Round 1: pre-ship comparison

Tested before the corpus-mean centering landed, to validate it was the right approach.

| variant | max raw | episodes >0.55 | episodes >0.70 | top-50 podcasts |
|---|---|---|---|---|
| **A** baseline (no post-processing) | 0.553 | 79 | 0 | **100% Gastropod** |
| **B** corpus-mean centering + re-normalize *(shipped)* | 0.718 | 2,071 | 1 | 23 Science History, 21 Gastropod, 3 Fresh From the Labs, 1 Dylan Curious (weekly, 1d), 1 Doom Debates (weekly, 3d), 1 Land of the Giants |
| **C** empirical baseline/spread remap of `(sim_pos − sim_neg)` | 0.983 | 5,984 | 3,764 | 21 Gastropod, 21 Science History, +misc |

Why B over C: C technically maxes out near 1.0 but is mis-calibrated — it stretches whatever the candidate distribution looks like onto `[0, 1]`, so 3,764 episodes scoring above 0.70 means "0.70" no longer means anything. C also doesn't address the underlying anisotropy — same Gastropod bias, just rescaled.

### Round 2: tricks beyond what we shipped

Tested seven more post-processing variants on top of variant B's foundation. Five target the cone problem more aggressively than mean-only centering; two swap the metric.

| variant | what it does | max raw | episodes >0.55 | top-50 distinct podcasts | top-1 podcast share |
|---|---|---|---|---|---|
| A baseline | none | 0.553 | 79 | 1 | 100% |
| **B** mean center *(originally shipped)* | subtract corpus mean, re-normalize | 0.718 | 2,071 | 6 | 46% |
| E1 all-but-the-top (k=1) | mean center + remove top-1 PC | 0.684 | 4,004 | 11 | 56% |
| E2 all-but-the-top (k=2) | mean center + remove top-2 PCs | 0.687 | 4,087 | 11 | 46% |
| **E3 all-but-the-top (k=3)** *(now shipped)* | mean center + remove top-3 PCs | 0.662 | 2,243 | **13** | **22%** |
| E4 all-but-the-top (k=4) | mean center + remove top-4 PCs | 0.675 | 2,657 | 10 | 36% |
| E5 all-but-the-top (k=5) | mean center + remove top-5 PCs | 0.644 | 1,350 | 4 | **84%** *(catastrophic)* |
| H ZCA whitening | full covariance normalization | 0.588 | 70 | 3 | 96% |
| I per-dim z-score | center + scale per dimension | 0.713 | 2,299 | 6 | 48% |
| J Mahalanobis similarity | center, then `aᵀ Σ⁻¹ b` instead of cosine | 0.599 | 73 | 3 | 96% |

### Top-10 trajectory across k for "all-but-the-top"

| variant | top 10 podcast composition | character |
|---|---|---|
| B (k=0) | 9 Gastropod, 1 Dylan Curious | one-podcast monopoly, on-topic |
| E1 (k=1) | 7 Morbid, 2 Gastropod, 1 Version History | format-axis lift, off-topic |
| E2 (k=2) | 5 Morbid, 4 Gastropod, 1 Version History | mixed, half off-topic |
| **E3 (k=3)** | **4 Fresh From the Labs, 2 Rest Is History, 2 Science History, 1 Gastropod, 1 Dylan Curious** | **diverse + on-topic — this is what we shipped** |
| E4 (k=4) | 6 Rest Is History, 1 Revisionist History, 1 Morbid, 1 Gastropod, 1 Fresh From the Labs | history-show dominance returns |
| E5 (k=5) | **10 Rest Is History** | catastrophic single-podcast collapse |

### Why E3 specifically — investigating Morbid

E1 and E2 both surface heavy doses of *Morbid* (true crime narratives) despite no Morbid episode being rated. Investigation showed the top 2 principal components of NLContextualEmbedding's corpus-centered matrix encode **"daily news/pundit show vs. long-form narrative storytelling"** — the podcasts most aligned with PC1+PC2 are Pivot, World in Brief, Morning Brew Daily, WSJ Tech News, Consider This (NPR), Bloomberg Daybreak, Up First (NPR), Apple News Today, Bloomberg Tech.

When E1 strips PC1 and E2 strips PC1+PC2, the residual centroid is dominated by the user's *narrative-format* preference (their loved/liked content is mostly long-form storytelling: The Last Invention, Hard Fork, Freakonomics, Radiolab-adjacent shows). Morbid then surfaces because it shares that *format* — not because of any topical match.

Direct check on Morbid's similarity to the user's positive centroid:

```
under B (k=0): +0.151
under E1 (k=1): much higher
under E2 (k=2): +0.371   (delta from B: +0.220 — more than doubled)
under E3 (k=3): drops out of top 10 entirely
```

E3 strips one more PC, which appears to encode something like "true crime narrative vs. analytical/explanatory narrative." Removing it cancels Morbid's lift and leaves the residual centroid actually correlated with the user's *content* preferences (tech, AI, science, history). The top 10 under E3 is dominated by Fresh From the Labs (AI/tech narrative, the user's actual interest area), Rest Is History (history narrative), Science History.

### Why not k=4 or k=5

E4 collapses partially into history-show dominance (6 of top 10 are Rest Is History — the user has 704 episodes of it in their library, and once enough orthogonal axes are stripped the remaining centroid direction projects strongly onto whatever happens to be densely represented). E5 is catastrophic: 10 of 10 top picks are Rest Is History, 84% of the top 50 — *worse* than B on the monopoly axis.

The general lesson: **top-k PC removal is not monotonically better**. There's a sweet spot determined by which axes the cone happens to encode for a given corpus. We empirically found it at k=3 for this library; the right k could differ for other users with different signal compositions, but the same Python harness in `score_variants_v2.py` can re-derive it.

### Why ZCA, Mahalanobis, and per-dim z-score didn't work

**ZCA whitening (H) and Mahalanobis (J) over-correct.** Both flatten the *entire* anisotropy spectrum, including dimensions that carry actual semantic signal. End result: similarity discrimination collapses below the baseline (only 70–73 episodes above 0.55, worse than the no-post-processing case). The scoring math gets dominated by the 0.5 + small-affinity-bump pattern again, and Gastropod's monopoly returns. The lesson: blindly equalizing all variance directions destroys what little signal NLContextualEmbedding produces.

**Per-dim z-score (I) is essentially indistinguishable from B.** The discriminative work was done by mean centering; per-dim scaling adds nothing.

## Future directions

Things worth revisiting if E3 starts to feel stale or another piece of the puzzle changes.

### Watch for at WWDC '26 (June 2026)

`FoundationModels` introduced the on-device 3B-parameter LLM in iOS 26 with no embedding surface. The natural next step — and one with precedent in how Apple has evolved similar APIs — is to expose either an embedding API derived from the same model or a separate `NLContextualEmbedding`-replacement built on the new model family. If that ships, it likely:

- Solves the cone problem (newer training regimes; potentially contrastive-tuned).
- Eliminates the bundle-size concern (model lives in the OS, not the app).
- Eliminates the tokenizer integration burden.
- Likely keeps the Apple-Intelligence-eligible-device gate, so older hardware would still need a fallback path (E3-on-`NLContextualEmbedding` is a reasonable one).

### CoreML-converted Sentence-BERT (if WWDC ships nothing relevant)

The realistic large move past `NLContextualEmbedding` is bundling a contrastive-trained model and running it via Core ML on the Neural Engine. Practical candidates as of 2026-05:

| model | dims | bundle (fp16) | MTEB retrieval | notes |
|---|---|---|---|---|
| `all-MiniLM-L6-v2` | 384 | ~22 MB | ~42 | Community CoreML port + Swift tokenizer + SwiftUI demo already exists |
| `BGE-small-en-v1.5` | 384 | ~33 MB | ~52 | Better quality, similar size |
| `gte-small` | 384 | ~33 MB | ~50 | Comparable to BGE |
| `BGE-base-en-v1.5` | 768 | ~110 MB | ~55 | Real quality jump; bundle size becomes a concern |
| `Qwen3-Embedding-0.6B` | up to 1024 | ~600 MB | ~64 | 2026 leader at small scale; brutal bundle size for an iOS app |

Realistic first move would be MiniLM-L6 as a proof-point — smallest bundle, existing port — followed by sizing up to BGE-small or BGE-base if discrimination is good but we want more headroom. The current decone machinery (cached transform, `recipeVersion`-keyed invalidation) carries over unchanged: even Sentence-BERT vectors are *near*-isotropic, not perfectly, and centering still helps at the margin. A `recipeVersion` bump on swap auto-invalidates the cached transform against the new model.

### Hybrid (server-precomputed embeddings)

Out of scope today — explicitly ruled out by the "no paid service or self-hosted server" constraint — but the architectural option still exists. Server bulk-embeds via the best cloud model, ships vectors as part of podcast metadata; clients do similarity math locally. This is how Spotify/Apple Music actually work. Best quality + on-device retrieval + zero per-user cost + perfect privacy (the server only sees public podcast feeds, not who's listening). Cost: standing up the embedding pipeline + a vector distribution channel.

### Re-derive E3's `k` per user

We picked `k=3` from a single library (mine). The right `k` likely depends on the signal composition: a user with a heavily news-skewed library might want a different stripping depth, and a user whose loved/liked content is nearly uniform across formats might do best at `k=0` (mean centering only). The Python harness in `score_variants_v2.py` makes per-user re-derivation cheap; if we ever want to personalize the depth instead of hardcoding 3, the same machinery could pick `k` automatically (e.g., the value that maximizes top-50 podcast diversity without collapsing to a single show).

### Things tried and confirmed not to work

So we don't re-litigate them:

- **ZCA whitening / full covariance normalization.** Over-corrects. Discrimination collapses below baseline.
- **Mahalanobis similarity** (`aᵀ Σ⁻¹ b` instead of cosine). Same failure mode as ZCA — flattens semantic signal along with cone bias.
- **Per-dim z-score / standardization.** Indistinguishable from plain mean centering.
- **k=4 or k=5 PC removal.** Strips actual topic signal; rankings collapse into single-podcast monopolies.
- **Empirical baseline-spread remap of similarity** (variant C from round 1). Mathematically rescales but doesn't address the underlying anisotropy; same Gastropod bias as baseline.

## Sources

- [Ethayarajh, "How contextual are contextualized word representations?"](https://kawine.github.io/blog/nlp/2020/02/03/contextual.html) — original BERT/ELMo/GPT-2 anisotropy analysis
- [Apple Foundation Models framework](https://developer.apple.com/documentation/FoundationModels) — confirmed: no public embedding API in iOS 26
- [`sentence-transformers/all-MiniLM-L6-v2` — CoreML port discussion](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/discussions/29)
- [`huggingface/swift-coreml-transformers`](https://github.com/huggingface/swift-coreml-transformers) — Swift package for Core ML transformer integration
- [MTEB leaderboard snapshot, March 2026](https://awesomeagents.ai/leaderboards/embedding-model-leaderboard-mteb-march-2026/)
- [Voyage 3-large announcement](https://blog.voyageai.com/2025/01/07/voyage-3-large/) — for the cloud-option benchmarks we ruled out
- [OpenAI text-embedding-3 announcement](https://openai.com/index/new-embedding-models-and-api-updates/) — same
