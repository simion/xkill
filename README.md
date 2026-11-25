# xkill for macOS

Click a window, its app dies. Like X11's `xkill`, but for the Mac.

Run `xkill` and the cursor turns into an ✕ on every screen and Desktop.
Click any window and its app is killed on the spot (`SIGKILL`), with a notification saying what died.
Esc or right-click cancels.

```sh
brew install simion/tap/xkill
```

Updates come with `brew upgrade`.

> **Warning:** this is the hard kill. The app gets no chance to save, so unsaved work is lost.

## Notes

- Only regular app windows can be picked, so a stray click can't kill the Dock, the menu bar or WindowServer.
- No special permissions needed.
- The notification is posted through `osascript`, so macOS lists it under **Script Editor**.
  If you don't see it, turn on System Settings → Notifications → Script Editor.
- If you have XQuartz, it ships its own X11 `xkill` in `/opt/X11/bin`; whichever comes first in your `PATH` wins.

## Build from source

```sh
swiftc -O xkill.swift -o xkill
./xkill --selftest   # prints "ok"
```

## Releasing

Push a `vX.Y.Z` tag. The release workflow publishes a GitHub release and bumps the formula in
[simion/homebrew-tap](https://github.com/simion/homebrew-tap), so `brew upgrade` picks it up.

## License

MIT
