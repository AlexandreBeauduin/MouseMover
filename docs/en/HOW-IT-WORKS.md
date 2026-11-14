# How it works

**English** · [Français](../fr/FONCTIONNEMENT.md) · [Nederlands](../nl/HOE-HET-WERKT.md) · [Deutsch](../de/FUNKTIONSWEISE.md)

## The cycle

While MouseMover is running, a one-second timer counts down the interval (shown in the menu
bar). At zero, MouseMover plays **one pattern** on the target display, then starts counting
again. *Run now* plays a cycle immediately without resetting the countdown.

Target display: the one chosen in *Display*, or the main display (*Follow main display*,
default; also used when the chosen display has been unplugged).

Mouse events are posted with `CGEvent` (`mouseMoved`, `leftMouseDown` / `leftMouseUp`), which
needs the **Accessibility** permission.

## Patterns

A pattern is an ordered list of points. Each point is a step:

1. **go** to the point;
2. optionally **wait** (a random pause between *At least* and *At most*);
3. optionally **click**.

| Setting | Meaning |
|---|---|
| Position | `x`, `y` from 0 to 1, as a fraction of the display; (0, 0) is the top left |
| Reference | *On screen*: the whole display. *Around the cursor*: (0.5, 0.5) is the cursor position when the cycle starts, the scale stays the display's |
| Path | *Fixed duration*: straight line at constant speed. Otherwise random, like a hand: a 1–4 px offset, 0.18–0.35 s, a random easing curve |
| Random order | shuffles the points on every cycle, except those that *Keep their place* |

Every target is kept 80 px away from the display edges, and every value is clamped into safe
bounds when a pattern is loaded (at most 200 points, moves of 0.05–3 s, pauses up to 5 s): a
badly written pattern cannot lock the mouse.

### Built-in patterns

| Pattern | Moves |
|---|---|
| Classic | center + click, the four corners in random order, back to the center |
| Discreet | a few pixels around the cursor, no click, back to the exact position |
| Circle | one circle around the center of the display, no click |
| Zigzag | a sweep from left to right, no click |

Built-in patterns cannot be edited: *Duplicate to edit* makes an editable copy.

### Which pattern plays

In *Manage patterns…* (or the *Pattern* submenu): *Always the same*, *Random among checked*
or *Each in turn*.

## Pattern editor

- Click in the frame to add a point, drag to move it; the inspector edits the selected point.
- Overlapping points: clicking the selected point of a stack selects the next one, and the
  inspector arrows move from point to point.
- *Test* plays the pattern right away.

### Capturing a gesture

*Capture a gesture* (5, 10 or 15 s): after a 3-second countdown, MouseMover samples the cursor
at 60 Hz and records left clicks, until the time is up or **Esc** is pressed. Clicks are really
performed during the recording.

The samples become a pattern:

- the cursor is considered still below 0.15 % of the display; a stop of 0.2 s or more becomes
  a pause; waiting before the first move and after the last one is dropped;
- the path is simplified (Douglas-Peucker, 0.4 % tolerance), keeping the start, the end,
  clicks and pauses;
- each point keeps its real duration, so the replay has the same rhythm.

## Fail-safe

As in the former Python version (pyautogui): if the cursor is at **(0, 0)** — the top-left
corner of the main display — before a move or a click, the cycle stops. MouseMover keeps
running and tries again at the next interval.

## Shortcuts

MouseMover provides actions to the Shortcuts app (App Intents): *Start MouseMover*,
*Stop MouseMover*, *Run MouseMover Now*, *Set MouseMover Interval*, *Choose MouseMover Display*
and *Choose MouseMover Pattern*. Their titles follow the macOS language; their answers follow
the language chosen in the app.

## Launch at login

`SMAppService.mainApp` — reliable only when the app lives in `/Applications`. If the
LaunchAgent of the former Python version (`~/Library/LaunchAgents/com.pudeldoodle.mousemover.plist`)
exists, the installed app replaces it with a native login item on first launch.

## Self-test

With the Accessibility permission, the app can play a real cycle and write a report:

```bash
/Applications/MouseMover.app/Contents/MacOS/MouseMover --self-test /tmp/report.json
```

It checks that the cursor really went near the four corners and back to the center.
