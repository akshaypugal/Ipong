# Tuning

The swing thresholds are tuned against synthetic swings, not a real wrist. Expect to adjust them on the first day.
All of them are exposed in **Settings > Developer mode > Debug > Swing thresholds** and are pushed to the Watch live.
Values are stored in the profile, so tune once and they stay.

## Workflow

1. Settings: turn on *Developer mode*, open **Debug**. The Watch goes to practice mode.
2. Play the stroke you care about ten times. The event log shows what the game read (`FOREHAND_TOPSPIN  86%`)
   and the Watch shows it locally.
3. Rejected or mislabelled strokes: read the *Decision* line (the burst the recogniser saw, its peak and why it was
   accepted or not) and change the threshold that separates the two strokes.
4. Press **Reset** to return to defaults.

## What each slider does

| Slider | Raise it when | Lower it when |
|---|---|---|
| Start threshold (g) | small movements trigger swings | soft strokes (drop, push) never register |
| Drive min (g) | drives are read as push/block | drives are rejected as too weak |
| Smash min (g) | normal drives become smashes | hard swings are only drives |
| Block max (g) | normal drives become blocks | blocks are read as drives |
| Drop max / Push max (g) | soft strokes are read as drives | drops/pushes are read as blocks |
| Flick gyro min (rad/s) | wrist rotation in normal swings makes flicks | real flicks are read as drives |
| Toss max peak (g) | swings are read as tosses | tosses are read as swings |
| Yaw side min (rad/s) | forehand/backhand is guessed wrongly | many strokes come out as side-less |
| Topspin vertical frac | flat drives become loops | loops are read as drives |
| Chop vertical frac (negative) | flat swings become chops | chops are read as drives |
| Confirm delay (s) | backswings turn into extra strokes | the stroke fires too late |
| Cooldown (s) | follow-throughs double count | rapid exchanges miss strokes |

## Feel and balance

- Timing window and reach come from the *reflex* upgrade and the opponent's reaction time.
- If the game feels late, check *Settings > Show latency in match* (average age of a swing when it reaches the phone). Anything
  above ~200 ms usually means the Watch app is not in a workout session or the Bluetooth link is busy.
- AI strength constants live in `AI/Opponents.swift`; shot error constants in `Game/ShotModel.swift`. The difficulty
  ladder is provisional. Run the slow balance table in the core tests with `PONG_BALANCE=1 swift test --filter MatchSimulationTests`.
