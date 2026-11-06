# WristPong

A full table tennis game for **iPhone + Apple Watch**. The Watch is your paddle, the iPhone is the table.

Swing your wrist and the game recognises the stroke you played: forehand or backhand drive, topspin loop,
backspin chop, push, smash, lob, block, drop shot, sidespin flick, plus the serve toss. The ball has real
physics (drag, spin/Magnus, spin-dependent bounces, net cord), the rules are ITTF rules, and there is a career,
a training academy, upgrades and daily challenges.

> **Status.** The game core (`Packages/PongCore`) is unit tested: 167 tests, run on Linux in Docker.
> The iPhone and Watch apps could not be compiled on the Windows PC they were written on: they were syntax-checked
> and code-reviewed only. Expect to fix a few compile errors on the first Mac build, and to tune swing
> thresholds on a real wrist. See [docs/SETUP.md](docs/SETUP.md) and [docs/TUNING.md](docs/TUNING.md).

## Quick start (Mac)

```bash
bash scripts/bootstrap.sh       # installs XcodeGen, runs core tests, generates WristPong.xcodeproj
open WristPong.xcodeproj
```

Set a unique bundle id and your team in `Config/Local.xcconfig`, run the **WristPong** scheme on your iPhone,
open the Watch app, calibrate, play. No Watch? Turn on **Settings > Simulated controller** (default in the
Simulator) and play with on-screen stroke buttons or the keyboard.

## The strokes

| Stroke | How you swing the Watch | Resulting ball |
|---|---|---|
| Toss (serve) | A small upward flick of the wrist | Ball goes up from your hand |
| Drive | Firm, flat swing through the ball | Fast and flat |
| Topspin loop | Brush up: low to high, quick wrist | Heavy topspin, dips and kicks |
| Backspin chop | Cut down: high to low | Backspin, floats, stops on bounce |
| Push | Short, soft downward touch | Low backspin ball to the short side |
| Smash | Full-power fast swing at a high ball | Hardest shot in the game |
| Lob | Slow, big upward swing | High defensive arc, deep |
| Block | Tiny quick stab | Uses the opponent's pace |
| Drop shot | Slow, soft touch | Dies just over the net |
| Sidespin flick | Sharp wrist flick across the ball | Curves in the air |

Forehand versus backhand comes from which way your wrist rotates through the swing (learned in calibration),
so it works whichever way you face. Timing decides placement and quality: swing when the ring around the
ball's strike point closes (PERFECT / GOOD / EARLY / LATE). Power follows how hard you swing relative to your
calibrated drive.

## Modes

- **Quick match**: pick any unlocked opponent, a format (quick to 7, best of 3, best of 5) and a Pro Tour tier.
- **Career**: six opponents with different styles (all-rounder, chopper, hard hitter, spin master, blocker, champion).
  Beat them to unlock the Pro Tour rematches.
- **Training**: eleven ball-machine drills, one per stroke including serves, with 1-3 stars.
- **Upgrades**: power, control, spin, reflex, bought with coins.
- **Daily challenges**, **stats**, **settings**, and a **Debug** screen with live sensor values, swing thresholds
  sliders and an event log.

## Layout

```
Packages/PongCore/   pure-Swift game core (physics, swing recognition, rules, AI, progression, wire protocol) + tests
iPhone/              SwiftUI game: court renderer, match view model, screens, services, Watch link
Watch/               Watch paddle: CoreMotion engine, calibration, haptics, workout session, small UI
iPhoneTests/         app-level tests (camera, choreography, router)
project.yml          XcodeGen project definition
docs/                SETUP, ARCHITECTURE, TUNING, TROUBLESHOOTING
```

## Docs

- [SETUP](docs/SETUP.md): build and run on a Mac, signing, Simulator, Windows workflow
- [ARCHITECTURE](docs/ARCHITECTURE.md): how the pieces fit
- [TUNING](docs/TUNING.md): making swings feel right
- [TROUBLESHOOTING](docs/TROUBLESHOOTING.md)
