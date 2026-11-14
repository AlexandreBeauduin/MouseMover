# MouseMover

[![CI](https://github.com/AlexandreBeauduin/MouseMover/actions/workflows/ci.yml/badge.svg)](https://github.com/AlexandreBeauduin/MouseMover/actions/workflows/ci.yml)

**English** · [Français](README.fr.md) · [Nederlands](README.nl.md) · [Deutsch](README.de.md)

A small macOS menu bar app that moves the mouse at regular intervals, along patterns you can
draw or record yourself, to keep the session awake and your status "active".

> **Vibe coded.** This project was built through conversation with an AI coding assistant
> (Claude Code): the human described what they wanted, tested on real hardware and steered;
> the AI wrote the code and docs. It works on the author's machine; read the code before
> trusting it on yours.

## Features

- **Start / Stop**, **Run now**, countdown to the next cycle in the menu bar.
- Interval: 1, 3, 5, 10, 15 minutes or custom.
- **Patterns**: four built-in ones (*Classic*, *Discreet*, *Circle*, *Zigzag*) and your own:
  - draw them point by point in the editor (click, pause, fixed or human-like path, order);
  - or **capture a gesture**: MouseMover records your real mouse moves and clicks;
  - on the screen or around the cursor, in order or shuffled;
  - play always the same one, a random one, or each in turn.
- Display choice (follows the main display by default), multi-display aware.
- **Fail-safe**: move the mouse to the top-left corner of the main display and the cycle stops.
- Launch at login.
- **Shortcuts** actions: start, stop, run now, set the interval, choose the display or the pattern.
- Interface in **English, French, Dutch and German**: follows the macOS language, or pick one
  in the menu (*Language*).

## Install

**Download:** grab `MouseMover-x.y.z.zip` from the
[Releases](https://github.com/AlexandreBeauduin/MouseMover/releases) page, unzip, move
`MouseMover.app` to `/Applications`. Universal binary (Apple Silicon + Intel), macOS 14+.

**From source** (Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
brew install xcodegen
scripts/build-app.sh --install   # builds and copies MouseMover.app to /Applications
```

A downloaded copy is not signed with a Developer ID: macOS blocks it on first launch →
System Settings › Privacy & Security › **Open Anyway**.

### Accessibility permission

Moving the mouse requires **System Settings › Privacy & Security › Accessibility**. MouseMover
asks on first launch; the menu shows *⚠︎ Allow Accessibility…* as long as it is missing.

macOS ties this permission to the app's signature. Release builds are signed ad hoc, so after
**each update** remove MouseMover from the list (−) and allow it again.

## How it works (short)

- Every interval, MouseMover plays one pattern on the chosen display with `CGEvent`
  (moves with easing curves, random pauses, optional clicks).
- A pattern is a list of points in fractions of the display (or of the area around the
  cursor); points without a fixed duration get a random, human-like path.
- Settings and patterns: `~/Library/Application Support/MouseMover/config.json`.

Details: [How it works](docs/en/HOW-IT-WORKS.md) · [Architecture](docs/en/ARCHITECTURE.md)

## Development

```bash
scripts/test.sh            # unit tests — no real mouse moved, no real login item
scripts/build-app.sh       # universal Release build in build/MouseMover.app + checks
scripts/release.sh         # build + build/MouseMover-<version>.zip (+ .sha256)
```

The Xcode project is generated from `project.yml` by XcodeGen (not committed). Builds are
signed ad hoc; to keep the Accessibility permission across your own rebuilds, sign with your
certificate in `Config/Local.xcconfig` (see `Config/Signing.xcconfig`).

Releasing: bump `MARKETING_VERSION` in `project.yml`, add a section to
[CHANGELOG.md](CHANGELOG.md), then push a matching tag (`git tag v2.1.0 && git push origin v2.1.0`):
GitHub Actions tests, builds and publishes the release.

## Caveats

- Clicks are real clicks: a pattern that clicks can act on whatever is under the cursor.
  The built-in *Classic* pattern clicks once in the middle of the display.
- Some apps or policies may still detect inactivity differently; MouseMover only simulates
  mouse input.

## License & disclaimer

MIT — see [LICENSE](LICENSE). Provided **as is, without any warranty**. This project is not
affiliated with or endorsed by Apple. Check your employer's rules before using it at work.
