# Troubleshooting

## The iPhone says the Watch is disconnected

- Open WristPong on the Watch and keep the wrist raised. Reachability only exists while the Watch app is in
  the foreground or in its workout session. Start a match: the iPhone asks the Watch to launch.
- Check the iPhone app is installed on the Watch (Watch app > My Watch > WristPong).
- Toggle Bluetooth off and on, or restart both devices. Settings shows the exact link state.
- Both targets need the HealthKit capability and a matching team; without it the Watch cannot be woken from the iPhone.

## Strokes are misread or missed

- Recalibrate (Settings > Calibrate) wearing the Watch exactly as you play. Calibration learns which way your wrist
  turns on a forehand; wearing the Watch on the other wrist or with the crown on the other side changes that.
- Use Debug to see the read stroke and confidence, then tune thresholds ([TUNING](TUNING.md)).
- Swinging too early or too late shows as EARLY / LATE; the ring on the table closes at the best moment.
- Backswings counted as strokes: raise *Confirm delay*. Follow-throughs counted twice: raise *Cooldown*.

## Strokes are late

Settings > Show latency in match. High numbers mean the Watch app is being throttled (no workout session: check
HealthKit permission) or Bluetooth is congested. The game compensates for latency up to 0.5 s but cannot recover
strokes that arrive later than that.

## The Watch app stops when I lower my wrist

The workout session keeps it alive. Accept the Health permission prompt on the Watch the first time. If you denied it,
re-enable in the Watch's Settings > Privacy > Health, or reinstall the Watch app.

## No sound

Check the silent switch is off, volume is up, and Settings > Sound is on. Sound effects are generated in code, so no files are missing.

## Xcode build errors on the first build

The app layer was written without a compiler. Fix the reported errors (they should be few and small), commit, and
push; CI shows the same errors on every push. The core package builds and tests independently: `swift test` in
`Packages/PongCore`.
