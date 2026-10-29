<p align="center">
    <img src="https://raw.githubusercontent.com/hedge-dev/UnleashedRecompResources/refs/heads/main/images/logo/Logo.png" width="512"/>
</p>

---

# Unleashed Recompiled for macOS

An unofficial, macOS-focused fork of [Unleashed Recompiled](https://github.com/hedge-dev/UnleashedRecomp), the static recompilation of the Xbox 360 version of Sonic Unleashed. It runs natively on Apple silicon, with no Rosetta, Wine or Game Porting Toolkit.

**Looking for Windows or Linux?** Use the [original project](https://github.com/hedge-dev/UnleashedRecomp). This fork only targets macOS.

**This project does not include any game assets. You must provide the files from your own legally acquired copy of the game.**

This fork is not affiliated with SEGA or with hedge-dev. All credit for the recompilation itself goes to the [original authors](docs/UPSTREAM_README.md#credits).

> [!NOTE]
> **AI-assisted.** Parts of this fork's macOS changes (code, patches and documentation) were written with the help of an AI coding assistant (Claude), then reviewed and tested on real hardware. The original Unleashed Recompiled project is the work of its authors and is unaffected by this note.

## What's Different on macOS

- **In-game updates.** New versions are announced on the title screen and installed through [Sparkle](https://sparkle-project.org).
- **Live HiDPI toggle.** Switch between native Retina and 1x rendering in Options → Video without restarting.
- **Fullscreen resolution list.** In fullscreen, pick from your display's real Retina ("HiDPI") or "looks like" modes, upscaled to the screen.
- **Resolution Scale shows the real resolution.** The slider label now includes the render size, such as `80% (1440x904)`.
- **Menu bar and Dock in fullscreen.** Optional: move the cursor to the screen edges to reveal them, so menu bar apps (temperatures and so on) and Quit stay reachable.
- **Mouse in menus.** Hover, click, right-click to cancel, and scroll in the Options menu. The cursor is shown everywhere except during gameplay.
- **Keyboard menu navigation.** Enter confirms and Escape backs out in menus (both pause during gameplay). Left and right switch Options tabs.
- **Retina and fullscreen fixes.** Correct mouse position in fullscreen, no flicker when changing scale, and a properly shaped Dock icon.

## Requirements

- A Mac with Apple silicon
- macOS 13 Ventura or later
- Your own copy of Sonic Unleashed for Xbox 360, plus the title update (DLC optional)

## Building

1. Install Xcode 16.3+ (or the Command Line Tools) and the build tools:

```bash
brew install cmake ninja pkg-config
```

2. Clone with submodules:

```bash
git clone --recurse-submodules <this repository>
```

3. Extract the three files the build needs from your own copy of the game:

```bash
python3 tools/macos/extract_game_files.py "<game>.iso" "<title update file>" UnleashedRecompLib/private
```

This writes `default.xex`, `shader.ar` and `default.xexp` into `UnleashedRecompLib/private/`. That folder is git-ignored: never commit or share its contents, or the generated `UnleashedRecompLib/ppc/` sources.

4. Configure and build:

```bash
cmake . --preset macos-release
```

```bash
cmake --build ./out/build/macos-release --target UnleashedRecomp
```

Configuring also applies this fork's fixes to the SDL, imgui and plume submodules from `thirdparty-patches/`. If configuring reports that a patch failed, run `git submodule update` and configure again.

5. Run it:

```bash
open "out/build/macos-release/UnleashedRecomp/Unleashed Recompiled.app"
```

The first launch opens the installer. Point it at your game, title update and DLC.

## Releasing

See [docs/RELEASING_MACOS.md](docs/RELEASING_MACOS.md) for signing, the Sparkle appcast and update keys.

## Everything Else

Features, keyboard bindings, save locations, mods and credits are covered in the [original README](docs/UPSTREAM_README.md).

## License

GPL-3.0, the same as the original project. See [COPYING](COPYING).
