# Architecture

```
 Apple Watch                                           iPhone
 -----------                                           ------
 CoreMotion (100 Hz)                                   SwiftUI game screen
   -> MotionSample                                       ^
   -> SwingRecognizer (pure Swift, PongCore)             | MatchSnapshot + MatchEvent
   -> PaddleEvent  --- WatchConnectivity ---> PaddleController --(age)--> MatchEngine
                                                         |                    |
 haptics <-------- PongHaptic <--------------------------+   PongCore: physics, rules, AI
 workout session keeps the sensors alive
```

The Watch decides *what stroke you played*. The iPhone decides *what happens to the ball*.

## PongCore (tested)

- **Physics** (`Physics/`): ball flight with drag and Magnus force, a table bounce model with friction (spin is gained
  and lost on contact), net clip/block, fixed 240 Hz step. `ShotSolver` finds the launch pitch and yaw that lands a shot
  on a target with a given speed and spin, including legal two-bounce serves and high lobs.
- **Swing recognition** (`Swing/`): filtering, gyro bias removal, burst detection, a feature vector (peak, speed,
  duration, vertical fraction, signed yaw integral), a pure classifier, validation (cooldown, rate limit, follow-through
  rejection) and backswing suppression by holding each event for `confirmDelay` (0.18 s). Events carry the sensor
  timestamp of the contact.
- **Game** (`Game/`): `MatchEngine` (phases, referee, strike timing, reach and reaction, drills), `ScoreKeeper` (ITTF scoring),
  `ShotModel` (quality, error, assist), drills.
- **AI** (`AI/`): `OpponentBrain` plays the same physics as the player, with six styles and per-opponent skills.
- **Progression** (`Progression/`): XP/levels, upgrades, daily challenges, settings, persistence.
- **Wire** (`Wire/`): plist-dictionary messages between Watch and iPhone, clock sync and latency statistics.

### Latency compensation

A swing reaches the iPhone 50-250 ms after the physical contact. `PaddleController` converts the sensor timestamp
into `age` using ping/pong clock sync. `MatchEngine.handle(_:age:)` rolls the ball back to the contact moment,
applies the hit there and re-simulates the flight to now, so wire latency does not turn a good swing into a late one.

### Strokes without a heading

No compass heading is needed. The stroke type comes from gravity-relative motion (up, down, flat) and wrist rotation
speed; forehand versus backhand comes from the sign of the yaw rotation (learned per player in calibration);
aim and placement come from timing.

## iPhone app

- `App/`: `WristPongApp`, `AppEnvironment` (profile, router, controller, sound, haptics).
- `Controller/`: `PaddleController` (the single input source: Watch or simulated), `PhoneLink` (WCSession), `WatchLauncher`
  (HealthKit `startWatchApp` to wake the Watch app).
- `Match/`: `MatchViewModel` (display-link game loop, events to banners, sounds and haptics), `CourtRenderer` (Canvas
  perspective court), `CourtGeometry` (camera, paddle choreography per stroke), `MatchView`, `SimPaddleView`.
- `Screens/`: home, quick match, career, training, results, upgrades, challenges, stats, settings, debug, calibration flow.
- `Services/`: generated sound effects, haptics, display link.

## Watch app

- `Motion/MotionEngine`: CoreMotion to `MotionSample` to recogniser, on a serial queue.
- `Motion/CalibrationRunner`: neutral, forehand, backhand capture; validates opposite wrist rotation.
- `Motion/WorkoutSessionManager`: a table tennis workout session keeps the app and sensors alive when the wrist
  drops. Nothing is saved to Health.
- `App/WatchModel`: ties it together; `.play` mode streams strokes to the iPhone, `.practice` shows them locally.
- `Feedback/WatchHaptics`: how each `PongHaptic` feels.
