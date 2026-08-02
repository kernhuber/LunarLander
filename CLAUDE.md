# Lunar Lander

A 2D Lunar Lander arcade game written in Swift with a custom Metal renderer. Ships on the App Store for iOS/iPadOS and runs locally on macOS.

## Targets and platforms

Two app targets share the same source files:

- **LunarLander** (macOS) — AppKit + storyboard. Bundle ID `de.kernhuber.LunarLander`, display name "Lunar Lander Vibes".
- **LunarLanderiOS** (iOS/iPadOS) — SwiftUI app entry, UIKit view controller. Bundle ID `de.kernhuber.LunarLanderMobile`, display name "Lunar Lander". Landscape only on iPhone, all orientations on iPad.

Shared source (compiled into both targets): `Renderer.swift`, `GameConfig.swift`, `HighscoreManager.swift`, `Shaders.metal`, `ShaderTypes.h`. Audio assets in `LunarLander/Assets/` are also shared.

Platform-specific files:
- macOS: `AppDelegate.swift`, `GameViewController.swift`, `Main.storyboard`
- iOS: `LunarLanderiOSApp.swift`, `iOSGameViewController.swift`

When changing shared code, build both targets — it's easy to break one while fixing the other.

## Architecture

`Renderer.swift` is the heart of the app (~1600 lines). It owns:
- Metal rendering pipeline and draw loop
- All game logic, physics, collision detection
- Vector font text rendering (no system text APIs)
- Particles, stars, terrain generation
- Game state machine

Game states: `logo → highscores → demo → (loop)` for the attract loop, and `playing → landed → levelTransition → (next level)` or `playing → crashed/tippedOver → gameOver → enteringName → highscores` for actual play.

Input is platform-specific and lives in the view controllers:
- macOS: NSEvent keyboard monitors. Space = thrust, arrows = lateral. Press R to start, number keys 1–9 select level (cheat).
- iOS: UIButton touch controls for thrust/lateral, UITextField for name entry.

Per-level physics (gravity, atmosphere drag, wind gusts, thrust scaling) live in `Renderer.swift`. 9 levels: Moon, Mars, Venus, Titan, Io, then cycling alien themes with progressive difficulty. Highscores persist as JSON via `HighscoreManager.swift`.

### Wind flag

Small pole at the right edge of the landing pad, only shown on wind levels (level 2+). Flag triangle points in the wind's direction; tip extends fully horizontal at high `|windForce|`, droops downward as wind weakens, vanishes entirely when nearly calm. Implemented in `drawWindFlag` and invoked from `drawLandingPad`.

### Floating objects

Floating objects spawn continuously at configurable rates per class (`GameConfig.lightObject`, `heavyObject`, `fuelObject` — singular structs of type `FloatingObjectClassConfig`) — see `tickRandomSpawning` for the formula `rate = spawnsPerSecond × spawnLevelMultiplier × currentLevel`. Each object enters from the off-screen left or right with a randomly chosen initial speed (also config-driven), an independent random rotation rate, and is discarded when it leaves the playfield. Three classes:

- **Light** — destroyed on contact, lander velocity unaffected, player score gains `obj.bonus` (configured per-pixmap, currently 10), and `onLightPickup` plays `blurp.mp3`. A floating "+N POINTS" popup appears at the hit point for 1 s.
- **Heavy** — triggers the standard crash sequence (`gameState = .crashed`, explosion particles, `onStateChange(.crashed)` plays the crash sound). Costs a life.
- **Fuel** — refills 40 % of the tank, the object vanishes, `onFuelPickup` fires the success sound. Max 1 fuel object on screen at any time; the spawn accumulator holds at 1.0 until the slot frees.

Pixmaps are loaded from disk at startup via `loadFloatingTextures(_:maxSize:)` — a generic routine that reads `(filename, bonus)` pairs from `GameConfig.lightObjects` / `heavyObjects` / `fuelObjects`, downsamples each PNG so its longer edge ≤ `s` (per-class `…MaxSize`), and pairs the resulting `MTLTexture` with its bonus. Renderer holds these as `lightTextures` / `heavyTextures` / `fuelTextures` and picks one at random per spawn. The display size in game units is taken directly from the loaded texture's pixel dimensions — so changing the `…MaxSize` values both downsamples the texture **and** shrinks the rendered sprite. The current `…MaxSize` values were tuned by hand (`/4` of the original suggestions) to keep sprites visible without dominating the playfield; leave them alone unless asked. Drawing is a single textured-quad pass via `texturePipeline` with the object's per-frame rotation applied to the four corners. Adding new artwork is just an entry in `GameConfig.swift` — no Renderer changes needed.

### Lives and crash retry

The player has 3 lives (`Renderer.maxLives`, decremented on every fail — ground crash, tip-over, fall off-screen, heavy-object collision; demo mode skipped). HUD shows `LIVES: N` color-coded green/yellow/red. On crash with lives remaining, the auto-transition to `.gameOver` is suppressed; the state holds and shows a `LIVES REMAINING: N` overlay plus (after a 0.6 s cooldown) a `PRESS ANY KEY` / `TAP TO CONTINUE` prompt. Input restarts the current level via `Renderer.retryCurrentLevel()`. When lives hit 0, the standard `gameOver → enteringName → highscores` flow runs.

### Score popups

Every light pickup spawns a `ScorePopup` at the hit position carrying `+N POINTS` (N from the per-pixmap bonus). Popups live 1.0 s, drift upward, fade by dimming, and are independent — multiple concurrent ones are supported. Reset on level start; tick at the top of `update()` so they keep fading even during `.crashed` / `.tippedOver`.

### Shield blasters

Limited-charge weapon that destroys heavy objects within a radius around the lander, giving the player an escape valve when heavies clog the approach. Refills to `GameConfig.maxShieldBlasters` (default 3) on every level start — a per-level resource, not per-run. HUD shows `SHIELD: N` directly below `LIVES`.

`Renderer.deployShieldBlaster()` is the trigger — only fires when `gameState == .playing` and charges remain. It appends an `ActiveShield` at the lander's current position; the energy ring then expands during the first half of `GameConfig.shieldBlasterDuration` and holds-with-alpha-fade during the second. Multiple shields can run concurrently. `updateShields(dt:)` ticks at the top of `update()` (independent of game state) and on each frame scans alive heavy floating objects against the shield's current radius — every heavy inside the ring is destroyed with a full crash-style particle explosion at its own position, and `onHeavyDestroyed` fires the crash sound on the host. `onShieldDeployed` fires `Shield.mp3` on deploy.

Drawing is 10 concentric cyan rings around the ship in `drawShieldBlasters` (called from `drawLandingPad`), with the alpha profile peaking at the actual radius and tapering inside/outside for a thick energy-band feel.

Input:
- macOS — Left Control via `NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)`, edge-detected (fires on the down transition only).
- iOS / iPadOS — teal `SHIELD` button (90×90) stacked above the thrust button on the left edge, fires on touch-down.

### Demo / attract loop

`setupDemo` runs `GameConfig.demoLevel` (Level 2 — wind + spawning so the demo can showcase shields). Time-capped at `GameConfig.demoMaxDuration` (30 s) but ends early on land/crash/tip. `updateDemoAI` uses deadband + hysteresis on both axes (no engine spam) and fires the shield when any heavy is within `shieldBlasterRadius` now or projected to enter within 0.4 s.

## Conventions

- Swift, 4-space indent. PascalCase for types, camelCase for members.
- SwiftUI uses `@State private var`; constants are `let`. Prefer Swift `async`/`await` over Combine.
- Avoid force unwrapping. Comments only when the *why* is non-obvious.
- The renderer does NOT use SpriteKit / SceneKit / system text. Drawing is hand-rolled Metal — match that style when adding visuals.

## Working in Xcode

This project is opened in Xcode. Prefer the `xcode-tools` MCP server:
- `BuildProject` to build (slow but authoritative).
- `XcodeRefreshCodeIssuesInFile` for fast per-file diagnostics.
- `ExecuteSnippet` to try a small piece of code without a full build.

Avoid command-line `find`/`ls` for project exploration — use `XcodeGlob`/`XcodeRead`/`Grep` instead so the user isn't pestered with permission prompts.

## App Store status

- iOS/iPadOS: live on the App Store. Marketing version now `3.5` build `1` locally — pending submission with the shield-blaster feature and demo improvements. Submission 5.2.5 rejection was resolved earlier by renaming the bundle ID from `LunarLanderiOS` to `LunarLanderMobile`.
- macOS: not on the App Store. Marketing version is `3.0` locally.
- Dev team: `3ZKRAY5KK8`.
- Encryption compliance (`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`) is now persisted in `project.pbxproj` across all build configs, so App Store Connect should no longer prompt for export compliance at upload.

## Planned next steps

- **Per-level graphics for floating objects.** Today every level draws from the same global `lightObjects` / `heavyObjects` / `fuelObjects` pools. The intent is to let each level pick from a different subset (or weighted subset) of pixmaps — e.g. junk-like items on Earth-analog levels, meteors and alien debris on outer-system levels. The shape will likely be a per-level map of `FloatingObjectType → [pixmap index]` or `[filename]` in `GameConfig.swift`, with `texturePool(for:)` consulting `currentLevel` when picking a spawn. The user plans to first redo the artwork so dangerous (heavy) and beneficial (light/fuel) items read more distinctly at a glance.

## Out of scope unless asked

- Don't refactor `Renderer.swift` into smaller files — it's intentionally monolithic.
- Don't add Combine, SwiftUI for the game view, or third-party dependencies.
- Don't touch macOS storyboard layout unless explicitly requested.
