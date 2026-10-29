# Releasing on macOS

Updates are delivered with [Sparkle 2](https://sparkle-project.org). Builds made without a feed URL and public key skip update checks entirely, which is the default for local development.

## One-time setup

1. Generate an EdDSA key pair. The private key goes into your login keychain, and the command prints the public key:

```bash
out/build/macos-release/Sparkle-2.6.4/bin/generate_keys
```

Back up the private key (`generate_keys -x <file>`) somewhere safe. Without it you can't ship updates to existing installs.

2. Pick where the appcast will live. A GitHub release asset works:
   `https://github.com/<you>/<repo>/releases/latest/download/appcast.xml`

## Each release

1. Bump the version in `UnleashedRecomp/res/version.txt`. Sparkle compares versions, so it must increase.

2. Configure with the feed and key, then build:

```bash
cmake . --preset macos-release -DUNLEASHED_RECOMP_SPARKLE_FEED_URL="<appcast URL>" -DUNLEASHED_RECOMP_SPARKLE_PUBLIC_KEY="<public key>"
```

```bash
cmake --build ./out/build/macos-release --target UnleashedRecomp
```

3. Sign the app with your Developer ID and notarize it. Unsigned or ad-hoc signed builds trigger Gatekeeper warnings, and Sparkle can't install over them cleanly.

4. Zip the app. `ditto` keeps symlinks and signatures intact:

```bash
ditto -c -k --keepParent "out/build/macos-release/UnleashedRecomp/Unleashed Recompiled.app" UnleashedRecomp-macOS.zip
```

5. Generate the appcast from a folder of release zips. This signs each update with your private key:

```bash
out/build/macos-release/Sparkle-2.6.4/bin/generate_appcast <folder with zips>
```

6. Upload the zip and `appcast.xml` to the location the feed URL points at.

## Game code and assets

The app binary contains code recompiled from the game's executable. The original project distributes binaries the same way, but redistributing them is your own legal responsibility. Never upload anything beyond the built app: no `UnleashedRecompLib/private/`, no generated `UnleashedRecompLib/ppc/` sources, and no installed game folder or assets.
