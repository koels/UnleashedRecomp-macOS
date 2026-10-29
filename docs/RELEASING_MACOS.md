# Releasing on macOS

Updates are delivered with [Sparkle 2](https://sparkle-project.org). The feed defaults to `appcast.xml` on this repository's latest GitHub release; configure with `-DUNLEASHED_RECOMP_SPARKLE_FEED_URL=""` to build without update checks.

## One-time setup

1. The EdDSA key pair already exists: the private key is in the login keychain under the `unleashed-recomp-macos` account, and its public key is the default of `UNLEASHED_RECOMP_SPARKLE_PUBLIC_KEY` in `CMakeLists.txt`. Pass `--account unleashed-recomp-macos` to every Sparkle tool so it uses this key and not another project's.

Back up the private key somewhere safe. Without it you can't ship updates to existing installs:

```bash
out/build/macos-release/Sparkle-2.6.4/bin/generate_keys --account unleashed-recomp-macos -x <backup file>
```

## Each release

1. Bump the version in `UnleashedRecomp/res/version.txt`. Sparkle compares versions, so it must increase.

2. Configure and build:

```bash
cmake . --preset macos-release
```

```bash
cmake --build ./out/build/macos-release --target UnleashedRecomp
```

3. Sign the app. With a Developer ID, sign and notarize it so it opens without warnings. Without one, ad-hoc sign it; Sparkle updates still install, but first-time users have to allow the app in System Settings → Privacy & Security:

```bash
codesign --force --deep -s - "out/build/macos-release/UnleashedRecomp/Unleashed Recompiled.app"
```

4. Zip the app. `ditto` keeps symlinks and signatures intact:

```bash
ditto -c -k --keepParent "out/build/macos-release/UnleashedRecomp/Unleashed Recompiled.app" UnleashedRecomp-macOS.zip
```

5. Generate the appcast from a folder of release zips. This signs each update with your private key:

```bash
out/build/macos-release/Sparkle-2.6.4/bin/generate_appcast --account unleashed-recomp-macos --download-url-prefix "https://github.com/koels/UnleashedRecomp-macOS/releases/download/<tag>/" <folder with zips>
```

6. Create a GitHub release for the tag and attach the zip and `appcast.xml`. The feed URL always resolves to the latest release's `appcast.xml`, so keep every past version in the folder from step 5 so the appcast lists them all.

## Game code and assets

The app binary contains code recompiled from the game's executable. The original project distributes binaries the same way, but redistributing them is your own legal responsibility. Never upload anything beyond the built app: no `UnleashedRecompLib/private/`, no generated `UnleashedRecompLib/ppc/` sources, and no installed game folder or assets.
