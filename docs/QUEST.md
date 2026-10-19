# Running on a Quest 3 by itself (standalone)

**Status: not done, not verified.** Everything here was written without a headset or the Android toolchain. It is the
checklist for ROADMAP Phase 1. The game has only ever run on the PC (and through Virtual Desktop).

## One-time setup
1. **Godot Android export templates** for 4.7.2 (Editor > Manage Export Templates), plus the Android SDK (platform-tools,
   build-tools, a JDK 17) and Godot's Editor Settings > Export > Android paths.
2. **Export preset**: Project > Export > Add > Android, name it `Quest`; architectures: arm64-v8a only; Gradle build on;
   package `com.jbax.vrbaseball`; XR mode: OpenXR; and the Meta OpenXR vendors plugin (Asset Library: "Godot OpenXR
   Vendors") enabled for Quest. Keep `export_presets.cfg` out of version control if it holds keystore passwords.
3. **Headset**: developer mode on, USB debugging allowed. `adb devices` must list it.

## Build and install
```
tools/deploy.sh --launch
```

## What to measure first (see ROADMAP Phase 1)
- Frame time in a busy play (double play with dust and sound), and the third-out frame (the off-screen half inning).
- `tools/perf.sh --demo --quest-budget` is the PC-side gate: 120 draw calls, 250k triangles, 80 Label3D, 160 MB video
  memory. These numbers are provisional until the device says otherwise.
- If the numbers ask: spread `HalfInningSim` over frames; bake board text into textures; convert audio to Ogg.

## Known things that will need attention
- Audio is 24 MB of PCM; Ogg for loops and music.
- 71 `Label3D` nodes for the boards.
- `user://` paths are fine on Android; the log and profile live in the app's private storage.
- No hand tracking is used; it is controllers only.
