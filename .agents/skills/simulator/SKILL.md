---
name: simulator
description: >-
  Build PodHaven (Development configuration) and run it on an iOS simulator.
  Use this whenever the user asks to "run on the simulator", "launch the sim",
  "build and run", "try it out in the sim", "open it on iPhone", or otherwise
  wants the current code running on a simulator they can interact with. Also
  use after a UI change when the user wants to verify the change visually.
user_invocable: true
argument: >-
  Optional simulator device name (e.g. "iPhone 16 Pro Max"). If omitted, the
  newest available iPhone under the newest installed iOS runtime is used.
---

# Run PodHaven on the iOS Simulator

Build the app, then launch it on a simulator. The order matters — see the rules at the bottom for why.

## Steps

### 1. Pick the device

If the user passed a device name as an argument (e.g. `iPhone 16 Pro Max`), use that verbatim. Otherwise, run the bundled helper to pick the newest available iPhone under the newest iOS runtime:

```bash
DEVICE="$(python3 .agents/skills/simulator/scripts/latest-iphone.py)"
```

If the helper fails (no iPhone simulators installed), tell the user and stop — don't guess.

### 2. Build (Development configuration)

Use `xcodebuild` against the project. **Always use the `Development` configuration** — the user does not use `Debug` or `Release` for day-to-day simulator runs.

```bash
xcodebuild \
  -project PodHaven.xcodeproj \
  -scheme PodHaven \
  -configuration Development \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -quiet build
```

Important:
- Do **not** pass `-derivedDataPath`. Letting xcodebuild use Xcode's default DerivedData makes the build incremental and shared with the user's Xcode.app session, which is dramatically faster than a clean build directory.
- Builds can take several minutes on a cold cache (Swift packages, swift-syntax, etc.). Run the build asynchronously / in the background if your runtime supports it, and wait for completion before moving on.
- If the build fails, surface the relevant errors to the user and stop. Do not proceed to install/launch a stale binary.

### 3. Locate the built `.app`

Don't try to construct the DerivedData path by hand — the hash directory name depends on the project path and Xcode version. Ask `xcodebuild` where it put the build output:

```bash
APP="$(
  xcodebuild \
    -project PodHaven.xcodeproj \
    -scheme PodHaven \
    -configuration Development \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -showBuildSettings 2>/dev/null \
  | awk -F' = ' '
      /[[:space:]]TARGET_BUILD_DIR =/ {td=$2}
      /[[:space:]]FULL_PRODUCT_NAME =/ {pn=$2}
      END {print td"/"pn}'
)"
```

`$APP` should now point at something like `…/DerivedData/PodHaven-<hash>/Build/Products/Development-iphonesimulator/PodHaven.app`. Confirm it exists (`ls -d "$APP"`) before continuing.

### 4. Boot the simulator and open the Simulator app

Now — and only now, after a successful build — bring up the simulator UI:

```bash
xcrun simctl boot "$DEVICE" 2>/dev/null || true   # already-booted is fine
open -a Simulator
```

### 5. Install, terminate any prior instance, and launch

The bundle id for the Development build is `com.artisanalsoftware.PodHaven.dev`.

```bash
BUNDLE_ID=com.artisanalsoftware.PodHaven.dev
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
```

The terminate step ensures that if a previous instance is still running on the device, the freshly installed binary is what actually starts — `simctl launch` will otherwise just foreground the stale process.

### 6. Confirm

Tell the user the app launched on `$DEVICE` and surface the PID that `simctl launch` printed. If you have any specific suggestion for what to try (e.g. the area you just changed), mention it briefly.

## Rules

- **Build first; touch the simulator only after the build succeeds.** Booting the simulator and opening Simulator.app eagerly while a multi-minute build is still compiling makes the empty simulator window look broken and is the first thing the user notices going wrong. Do all of step 4 onward only after step 2 returns success.
- **Always Development, never Debug or Release** unless the user explicitly says otherwise. Bundle id is `com.artisanalsoftware.PodHaven.dev`; the Debug and Release configurations use different bundle ids and are not the user's normal workflow.
- **Don't guess the `.app` path.** Always derive it from `xcodebuild -showBuildSettings` so it works regardless of Xcode version, worktree location, or DerivedData hash changes.
- **Don't pass `-derivedDataPath`.** A separate build directory forces a full cold rebuild of every Swift package dependency every time, which can take 10+ minutes. The default DerivedData is incremental.
