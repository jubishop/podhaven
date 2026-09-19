---
status: current
---

# CarPlay MVP automated acceptance

Issue [#631](https://github.com/jubishop/podhaven/issues/631) accepts automated
behavior, isolated preview builds, and signed configuration checks for the
Up Next, Episodes, Podcasts, and Now Playing milestone. Siri media intents and
assistant cells remain in [#632](https://github.com/jubishop/podhaven/issues/632);
the parent [#625](https://github.com/jubishop/podhaven/issues/625) stays open.

The tests construct real CarPlay template objects and run the production
coordinator, browsing queries, selection, shared player, command handling, and
widget snapshot writer. Fakes replace the interface controller, audio session,
media assets/player, notifications, files, and remote command center. Database
fixtures are isolated and in memory. Repository spies delegate ordinary work to
the real repository. This evidence proves application behavior at those
boundaries. It does not prove CarPlay's renderer or physical audio behavior.

## Evidence matrix

All suites below are in `PodHavenTests`. The linked PR records the final
revision, full-suite result, signed artifacts, raw log paths, and result-bundle
validation. A passing focused suite alone does not complete acceptance.

| Area and cases | Automated evidence | Limits |
| --- | --- | --- |
| Cold CarPlay connection without phone activity; saved paused/playing episode; slow and failed restoration; shared readiness; phone scene phase | `CarPlaySceneTests`: `coldConnection`, `pendingMediaRestoration`, `simultaneousReadiness`, `preservesPlayback`, `phoneScenePhase`; `BackgroundCommandCenterLaunchTests` | The fixture invokes production startup/coordinator entry points. It does not launch a locked installed app. Foreground services are intentionally disabled in the test environment. |
| Disconnect during root initialization, lookup, accepted load, query, and artwork; reconnect; reused controller; old completions; repeated cycles; observer and handler release | `CarPlaySceneTests`, `CarPlaySelectionTests`, `CarPlayPodcastRecoveryTests.staleDestinationsAndArtwork`, `CarPlayListTests.artwork`, `CarPlaySmartListRecoveryTests.delayedDefinition`, `CarPlayIntegrationTests.interruptionAndReconnect` | Controlled completion ordering proves stale work cannot navigate or stop shared playback. Physical wired/wireless transport and process termination are unverified. |
| Every root/detail flow; All Podcasts/All Episodes; saved ordering and Smart List sorts; empty/error/retry states; oversized lists; runtime restrictions; deletion below Now Playing; Back and tabs | `CarPlayPodcastTests`, `CarPlayPodcastNavigationTests`, `CarPlayPodcastRecoveryTests`, `CarPlaySmartListTests`, `CarPlaySmartListNavigationTests`, `CarPlaySmartListRecoveryTests`, `CarPlayListTests`, `CarPlayNowPlayingTests`; `CarPlayIntegrationTests.sharedSurfaces` crosses the assembled browsers | Restricted item/section budgets and bounded template stacks are exercised. Native layout and the head unit's own navigation are unverified. |
| Repeated taps; competing phone/remote requests; cached/streamed playback; failed/stalled loads; unavailable/deleted rows | `CarPlaySelectionTests`, `PlaybackIntentOwnershipTests`, `CarPlayPlaybackTests`; `CarPlayIntegrationTests.sharedSurfaces` also changes episode through `PlayEpisodeIntent` | Fake asset URLs distinguish file and remote playback. No network or physical media transport is required by these tests. |
| No audio activation or autoplay during connection/browse; preserve another source until explicit play; interruption pause/resume; route changes; media-services reset; repeated reconnect | `CarPlaySceneTests.coldConnection` and `preservesPlayback`, `CarPlayPlaybackTests.queueProjection`, browser suites' activation assertions, `PlaybackControlsTests`, `RouteChangeRecoveryTests`, `MediaServicesResetTests`; `CarPlayIntegrationTests.mediaServicesRecovery` and `interruptionAndReconnect` | No activation call is the application-side evidence for leaving other audio alone. Actual FM, other apps, calls, spoken Siri, route loss, and wired/wireless audio remain unverified. Interruption notifications do not identify or simulate a caller or spoken Siri session. |
| After-first-unlock readiness; database and SQLite sidecars; cached media; required settings; unavailable data | [Protected storage audit](carplay-lifecycle.md#protected-storage-audit); `CarPlaySceneTests` restoration cases; real database query failures and native Retry in podcast and Smart List recovery suites; selection load failures | Source/configuration audit only for protection classes. Inaccessible bootstrap databases are fatal before a scene is created. Before-first-unlock access is unsupported; tests do not establish installed-file attributes or relocked access. A query failure is not evidence that protected storage was unlocked. |
| Text/fallbacks; selectable/loading/progress states; long multilingual text; content order | `CarPlayListTests.semantics`, browser empty/loading/error/restriction tests, `CarPlaySelectionTests` completion/deadline tests, `CarPlayIntegrationTests.sharedSurfaces`; isolated preview fixtures listed below | Full native row text, metadata, progress, and handlers are inspectable. VoiceOver reading/focus order, truncation, touch/rotary/touchpad, light/dark rendering, and screen shapes are unverified. Multilingual input is not an app-localization claim. |
| Shared episode, progress, queue, rate, and command availability across phone state, lock-screen/headphone commands, widgets, and CarPlay | `CarPlayIntegrationTests.sharedSurfaces`: Smart List selection, shared metadata, widget snapshots, widget pause, remote Play/rate/seek, Up Next progress, podcast detail/Back, and widget episode replacement; `NowPlayingInfoTests`, `WidgetSnapshotWriterTests`, shared command regressions | Tests exercise the same application command and snapshot pipelines. Physical phone, lock-screen, headphones, and widget interaction remain unverified. Widgets expose the fields their existing snapshot/control contracts provide; they do not acquire a CarPlay-specific rate field. |

## Recovery and ownership

The integrated media-services-reset test begins with playing audio, delivers
the actual reset notification through the notification boundary, and waits for
the retired player to be replaced. It selects the preserved episode in Up Next,
opens Now Playing, and resumes with the shared remote Play command at the saved
position. It never invokes the phone alert's action. A successful cold launch
does not substitute for this recovery test.

Repeated interruption/reconnect coverage checks one Now Playing observer while
connected, no observer/buttons/controller delegate after disconnect, and the
same underlying player item before and after reconnection. Selection suites
separately prove that disconnect completes outstanding callbacks exactly once
without cancelling an accepted shared-player load.

## Graphical and signed-build checks

The existing isolated `#Preview` fixtures cover root placeholders/retry,
Up Next/current/progress/empty content, and the podcast and Smart List states:
loading, empty, populated, failed, restricted, and ranking unavailable. Their
files are `CarPlayRootTemplate.swift`, `CarPlayEpisodeList.swift`,
`CarPlayPodcastPreviews.swift`, and `CarPlaySmartListPreviews.swift` under
`PodHaven/CarPlay`. They use static content without network or persistent data.
A Debug Simulator build compiles these fixtures. It does not render native
CarPlay templates or establish visual accessibility acceptance.

For the final tree, retain a signed Debug Simulator build and a Release iOS
archive exported locally with the App Store Connect method and
`destination = export`. Do not use `bin/deploy.sh` for this validation because
that command uploads. Inspect the exported app's code signature and embedded
provisioning profile, including the widget/share extensions. Verify CarPlay
Audio, app groups, associated domains, background audio, and the scene manifest.
Simulator signing does not use an embedded iOS distribution profile.

No TestFlight upload, installation on a physical device, debugger attachment,
or native CarPlay inspection is part of this acceptance run.

## Reproduce the automated checks

Run from this checkout using the supported Xcode and macOS versions:

```sh
mkdir -p .cache/carplay-validation
bin/with-test-accessibility xcodebuild test -hideShellScriptEnvironment \
  -project PodHaven.xcodeproj -scheme PodHaven -testPlan PodHaven \
  -destination 'platform=macOS,name=My Mac' -skipMacroValidation \
  -only-testing:PodHavenTests/CarPlayIntegrationTests \
  -resultBundlePath .cache/carplay-validation/integration.xcresult \
  LM_FORCE_LINK_GENERATION=YES \
  > .cache/carplay-validation/integration.log 2>&1
bin/check-swift-results .cache/carplay-validation/integration.xcresult \
  --build-log .cache/carplay-validation/integration.log
```

Use a new result-bundle path for each attempt. After committing the complete
change, run fresh `bin/test-all --ensure --revision <full-sha>` from a clean
checkout. Verify its revision, before/after checkout fingerprint, zero skipped
tests, raw warnings, result-bundle diagnostics, and `run.json` outcome. Retain
the `.cache/test-all/` evidence with the operation. Follow the
[Swift validation workflow](development-workflow.md#current-revision-swift-validation).

Native/device limitations above remain informational. They neither establish
hardware success nor create merge or issue-closing prerequisites. Known
application defects and failed automated or signing checks still block delivery.
