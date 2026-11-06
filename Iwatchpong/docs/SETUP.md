# Setup

## What you need

- A Mac with Xcode 15 or later (iOS 16 / watchOS 9 or later targets)
- An iPhone paired with an Apple Watch (Series 4 or later recommended)
- An Apple ID. A free account can install on your own devices for 7 days at a time; HealthKit capability works with a
  free account for development, but a paid account is needed for TestFlight.

You cannot build the iPhone or Watch app on Windows. The core package (`Packages/PongCore`) is plain Swift
and its tests run anywhere Swift runs (Linux, Docker, macOS).

## First build

```bash
git clone <your repo> && cd Iwatchpong
bash scripts/bootstrap.sh
```

The script installs XcodeGen with Homebrew if needed, runs `swift test` on the core, creates
`Config/Local.xcconfig` from the example on the first run, generates `WristPong.xcodeproj` and opens it.

1. Edit `Config/Local.xcconfig`: set `APP_BUNDLE_ID` to something unique (for example `com.yourname.wristpong`) and,
   optionally, `DEVELOPMENT_TEAM`. Re-run `xcodegen generate`.
2. In Xcode, select the **WristPong** scheme and your iPhone. In *Signing & Capabilities* for both targets
   (WristPong, WristPongWatch) pick your team if it is not set yet. Both need the **HealthKit** capability.
3. Run. Xcode installs the iPhone app and the embedded Watch app. If the Watch app does not appear, open the Watch
   app on the iPhone > My Watch > WristPong > Install.
4. Open WristPong on the iPhone. First launch shows the setup flow: connect and calibrate (below).

## Calibration

The Watch walks you through three captures, shown on both screens:

1. **Hold still** (3 seconds): measures the sensor baseline.
2. **Forehand**: one forehand drive with a natural wrist turn.
3. **Backhand**: one backhand drive. It must turn the wrist the opposite way; otherwise it asks again.

Then you can try strokes on the "Try some strokes" screen and see what the game reads. Recalibrate any time
from Settings, and wear the Watch the way you will play (which wrist, which way up).

## Simulator and developer controller

The Simulator has no Watch. The app turns on **Simulated controller** automatically there: every stroke is a button
and a keyboard shortcut (space = toss, F/B = forehand/backhand drive, T/Y = loops, C = chop, P = push, S = smash,
L = lob, K = block, D = drop, flick left/right on the buttons). This is also a quick way to check game balance on
a real iPhone without wearing the Watch.

## CI

`.github/workflows/ci.yml` runs the core tests on Linux, then on a macOS runner generates the project with XcodeGen
and builds the iPhone app, the Watch app and runs the iPhone unit tests. The first CI run on macOS is the first
time the app code is compiled: read its log for the list of things to fix.

## Windows workflow

Edit and run core tests on Windows with Docker:

```bash
docker run --rm -v "$(pwd):/pkg" -w /pkg/Packages/PongCore swift:5.10 swift test
```

Push to git, then build on the Mac (or let the CI macOS runner do it).
