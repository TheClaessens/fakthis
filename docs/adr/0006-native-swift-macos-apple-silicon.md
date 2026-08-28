---
status: accepted
---

# Fakthis is a native Swift macOS app on Apple Silicon

The original draft treated runtime as an implementation detail, then as a process-spawn problem. ADR-0001 removed the spawn constraint; ADR-0003 replaced it. Fakthis is a **native Swift / SwiftUI app, macOS, Apple Silicon, one process**. The deciding constraint is FluidAudio: a Swift package running CoreML on the Neural Engine. A browser cannot host it, and a web shell would exist only to keep a UI whose cross-platform pitch the ANE already killed.

## Considered Options

**PWA with filesystem access.** Dead. Neither FluidAudio nor whisper.cpp runs in a browser. Jira Cloud REST also refuses arbitrary browser origins (CORS), so even without transcription a PWA would need a backend Fakthis is not allowed to have.

**Electron or Tauri plus a Swift sidecar.** Rejected. The sidecar is all cost: IPC on the mic path, two binaries to package, a second HTTP stack for Jira, a second Keychain binding. What it buys is a web UI and a cross-platform shell. The UI is real work, but v1 has one user on a Mac, and “cross-platform” is not a property this app can have while the transcriber needs the ANE.

**Native Swift, SwiftUI, one process.** Chosen. FluidAudio is a first-class dependency. URLSession talks to Jira with no CORS. whisper.cpp links as the bundled fallback. Keychain Services holds the two user-supplied keys. Files live under Application Support.

## Consequences

- **macOS on Apple Silicon is a floor, said out loud.** Not “desktop.” Not Intel. Not iOS. Published FluidAudio numbers are M2/M4; this CoreML path has no useful Intel story.
- **User #2 still pastes their own keys into their own Keychain.** A key compiled into the `.app` stays forbidden. Packaging and how Thomas installs are still deferred; the runtime is not.
- **The agent loop, the transcriber, and Jira I/O share one process.** There is no sidecar contract to design, and no Chromium to ship next to 350 MB–1.6 GB of models.

Decision ticket: https://github.com/TheClaessens/fakthis/issues/12
