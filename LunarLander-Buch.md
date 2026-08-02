# Lunar Lander — Ein Lehrbuch über Swift, Metal und Spieleentwicklung im Apple-Umfeld

> Dieses Buch begleitet den Quellcode des Projekts `LunarLander` in diesem Repository. Es richtet sich an einen erfahrenen Informatiker mit Vorkenntnissen in C/C++/Java/Python, Assembler, Game-Architektur und 3D/Grafik. Swift selbst wird deshalb mehr Raum als alles andere bekommen — die Konzepte rund um Spiele- und Grafikprogrammierung werden zwar präsentiert, aber nicht von Null aufgebaut.

> 🌐 Ergänzend gibt es eine aus [`GAME_SPEC.md`](GAME_SPEC.md) abgeleitete **JavaScript-Portierung** (im Browser lauffähig, noch in Arbeit): <https://turbonerd.org/lunarlander/>.

---

## Inhaltsverzeichnis

1. Einführung und Übersicht über das LunarLander-Projekt
2. Konzeptionelle Übersicht über die Entwicklung im Apple-Environment
3. Generelle Architektur des Spiels
   - 3.1 Design-Entscheidungen
   - 3.2 Funktionsblöcke
   - 3.3 Zusammenspiel der Einheiten
4. Details — der Code im Einzelnen
   - 4.1 Swift-Crashkurs für C/C++/Java-Veteranen
   - 4.2 `ShaderTypes.h` — die Brücke zwischen CPU und GPU
   - 4.3 `GameConfig.swift` — zentrale Konfiguration
   - 4.4 `HighscoreManager.swift` — Persistenz mit `Codable`
   - 4.5 `AppDelegate.swift` und der macOS-Lifecycle
   - 4.6 `GameViewController.swift` (macOS) — Input, Audio, Lifecycle
   - 4.7 `LunarLanderiOSApp.swift` — SwiftUI als App-Entry
   - 4.8 `iOSGameViewController.swift` — UIKit-Einbettung
   - 4.9 `Renderer.swift` — das Herz des Spiels
5. Metal Shaders — `Shaders.metal` im Detail
6. Code Review

---

## 1. Einführung und Übersicht über das LunarLander-Projekt

`LunarLander` ist ein klassisch anmutendes 2D-Arcade-Spiel. Der Spieler steuert eine Landefähre, die unter Gravitations- und Windeinfluss auf einer wechselnden Planetenoberfläche sicher absetzen soll. Es gibt **9 Levels** (Mond, Mars, Venus, Titan, Io und vier zyklische "Alien"-Welten), **3 Leben**, Treibstoff, Höhenmesser, Punktebonus, Highscore-Tabelle und einen ständig laufenden **Attract-Loop** (Logo → Highscores → Demo → Logo …) wie in den Spielhallen der 80er.

Was das Projekt aus didaktischer Sicht interessant macht:

- Es spannt das **gesamte Apple-Ökosystem** auf, das man als Spieleentwickler praktisch berührt: AppKit (macOS), UIKit (iOS), SwiftUI (Entry-Point), Metal (GPU), MetalKit (`MTKView`), AVFoundation (Audio), Foundation (`Codable`, `FileManager`, …).
- Es zeigt **zwei App-Targets aus einer gemeinsamen Code-Basis** — fast die ganze Spiellogik liegt in *einer* Datei (`Renderer.swift`), die in beide Targets reinkompiliert wird.
- Es nutzt **keine** der Apple-Hochlevelschichten für Spiele (SpriteKit, SceneKit) und **keine** System-Textrendering-APIs. Stattdessen werden Vektoren, Linien, Dreiecke und ein selbstgebauter Vektor-Font direkt über Metal hochgeladen. Wer aus der "ich male einen Treiber für mein Pixel-Framebuffer"-Welt kommt, fühlt sich sofort heimisch.
- Die Architektur ist bewusst **monolithisch** (1 großer `Renderer`), aber sauber konfigurierbar und mit Callbacks von der View-Controller-Schicht entkoppelt.

Das Spiel ist auf dem App Store live (iOS/iPadOS, Bundle-ID `de.kernhuber.LunarLanderMobile`); auf macOS läuft es ausschließlich lokal. Es zeigt also gleichzeitig einen *Produktions-Workflow* (Signing, Bundle-IDs, Export-Compliance) und einen reinen *Dev-Workflow*.

### 1.1 Erwartungshorizont des Buches

- Du wirst nach diesem Buch in der Lage sein, ein nicht-triviales 2D-Spiel in Swift mit Metal zu lesen, zu warten und zu erweitern.
- Du wirst die Bauteile *erkennen*, mit denen Apple-Apps zusammengesetzt sind, und wirst wissen, *welches* Werkzeug zu welcher Aufgabe gehört.
- Du wirst Swift-Idiome verstehen, die in der offiziellen Doku gerne unkommentiert vorausgesetzt werden (Closures mit `[weak self]`, Optionals, `guard`, Generics, `Codable`).
- Du bekommst am Ende ein ehrliches **Code Review** mit Stärken, Schwächen und Vorschlägen — kein Marketing.

### 1.2 Projektstruktur auf einen Blick

```
LunarLander/                              ← Quellverzeichnis (macOS + shared)
  AppDelegate.swift                       macOS-Entry
  GameViewController.swift                macOS-View-Controller (AppKit)
  Renderer.swift                          ALLES Spiellogik + Metal-Rendering (~2070 LOC)
  GameConfig.swift                        zentrale Konstanten/Konfiguration
  HighscoreManager.swift                  JSON-Persistenz für Highscores
  Shaders.metal                           GPU-Shader (Metal Shading Language)
  ShaderTypes.h                           gemeinsame Typen zwischen Swift und Metal
  Assets/                                 Audio + PNGs
  Assets.xcassets, Base.lproj/Main.storyboard

LunarLanderiOS/
  LunarLanderiOSApp.swift                 SwiftUI-Entry
  iOSGameViewController.swift             UIKit-View-Controller, Touch-Steuerung
  Assets.xcassets

LunarLander.xcodeproj/                    Xcode-Projektdatei
```

Beide App-Targets ziehen die Dateien aus `LunarLander/` (außer `AppDelegate.swift`, `GameViewController.swift`, `Main.storyboard`) ins iOS-Target hinein und werden gegen unterschiedliche SDKs gebaut.

---

## 2. Konzeptionelle Übersicht über die Entwicklung im Apple-Environment

Wenn du aus der Linux/Win/Cross-Plattform-Welt kommst, ist das Apple-Stack zunächst eine Wand aus Akronymen. Hier eine ehrliche, schichtweise Übersicht — nur das, was du für dieses Projekt brauchst.

### 2.1 Sprachen

- **Swift** ist die Hauptsprache. Sie ist eine moderne, statisch typisierte, ARC-verwaltete (Automatic Reference Counting) Sprache mit Generics, Protokollen, Closures, Pattern-Matching, optionalen Typen, Wert- vs. Referenztypen (`struct` vs. `class`). Sie kompiliert nativ via LLVM. Aus C-Sicht: "C++ ohne die historischen Wunden + Haskell-Anleihen + Java-mäßige ARC".
- **Objective-C** war der Vorgänger. Wir berühren ihn hier *einmal* — `ShaderTypes.h` ist eine `.h`-Datei, die sowohl Swift (per Bridging-Header) als auch der Metal-Compiler einliest. Das ist der eleganteste Weg, um Datenstrukturen zwischen GPU und CPU zu teilen.
- **Metal Shading Language (MSL)** ist eine C++14-Untermenge mit GPU-spezifischen Attributen (`[[position]]`, `[[buffer(0)]]`, `[[vertex_id]]`). Sie lebt in `.metal`-Dateien.

### 2.2 Frameworks ("Schichten")

Apple gruppiert seine Frameworks in *Layer*. Für uns relevant:

| Framework             | Schicht | Rolle hier                                                                |
| --------------------- | ------- | -------------------------------------------------------------------------- |
| **Foundation**        | Core    | Standard-Bibliothek: `URL`, `FileManager`, `JSONEncoder`, `Bundle`, `Timer` |
| **AppKit** (`Cocoa`)  | UI mac  | `NSApplicationDelegate`, `NSViewController`, `NSEvent`, Storyboards         |
| **UIKit**             | UI iOS  | `UIViewController`, `UIButton`, `UITextField`, Touch-Events                 |
| **SwiftUI**           | UI new  | Hier nur als App-Entry für das iOS-Target verwendet                         |
| **Metal**             | GPU     | `MTLDevice`, `MTLCommandQueue`, `MTLBuffer`, Pipelines, Shader              |
| **MetalKit**          | GPU+UI  | `MTKView` (eine View, die die Metal-Drawable-Loop verwaltet), `MTKTextureLoader` |
| **AVFoundation**      | Audio   | `AVAudioPlayer`, `AVAudioSession`                                          |
| **simd**              | Math    | SIMD-Vektoren `SIMD2<Float>`, `SIMD4<Float>` mit GPU-kompatiblem Layout    |
| **CoreGraphics**      | 2D      | `CGImage`, `CGContext` — hier zum Skalieren der Pixmaps                    |
| **ImageIO**           | Decode  | `CGImageSourceCreateWithURL` zum Laden von PNGs                            |

**Wichtig:** Apple-Frameworks haben überlappende Verantwortlichkeiten. `MTKView` ist z. B. von `UIView`/`NSView` abgeleitet, je nach Plattform. Eine View kann gleichzeitig "AppKit-Bürger" und "Metal-Drawable-Host" sein. Diese Mehrfach-Identität ist normal und macht den Code knapper.

### 2.3 Build-System

- **Xcode** ist gleichzeitig IDE, Build-System und Asset-Pipeline. Es gibt keine separate `Makefile`/`CMakeLists.txt` — Xcode hält alle Build-Optionen in der `.xcodeproj/project.pbxproj` (ein Property-List-/Plist-ähnliches Textformat).
- Du arbeitest mit **Targets** (eine ausführbare Einheit, hier `LunarLander` und `LunarLanderiOS`), **Build-Phasen** (Compile Sources, Copy Bundle Resources, Link Binary) und **Schemes** (eine Run-Konfiguration).
- Ein **Bundle** ist die `.app`-Datei: ein Verzeichnis, das Binary, Ressourcen und ein `Info.plist` enthält. Beim Zugriff auf Assets zur Laufzeit nutzt man `Bundle.main.url(forResource:withExtension:)`.

### 2.4 Codesigning, Provisioning, App Store

- Jedes ausgelieferte Apple-Programm muss **signiert** sein. Beim Mac für *dich* (Apple Developer ID, hier Team `3ZKRAY5KK8`), beim iPhone vor App-Store-Distribution mit einem **Provisioning Profile**.
- **Bundle-Identifier** sind global eindeutig (`de.kernhuber.LunarLanderMobile`).
- **Export-Compliance**: `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` erspart einen US-Verschlüsselungs-Fragebogen pro Upload.

Du musst das nicht im Detail beherrschen, um den Code zu lesen — aber wenn du eigene Builds verteilen willst, läufst du in diese Wand. Erwarte das.

### 2.5 ARC (Automatic Reference Counting)

Swift hat keinen Garbage Collector. Stattdessen fügt der Compiler `retain`/`release`-Befehle in den Maschinencode ein. Konsequenzen, die im Code auftauchen:

- Closures, die `self` einfangen, erzeugen Zyklen, wenn `self` die Closure besitzt. Lösung: `[weak self]` (siehe `GameViewController.swift`).
- `class` ist Referenz-Typ; `struct` und `enum` sind Wert-Typen.
- Wenn du Objekte als `var` hältst, hältst du *automatisch* eine starke Referenz. Es gibt `weak`, `unowned` als Annotationen.

### 2.6 SwiftUI vs. AppKit vs. UIKit

- SwiftUI ist Apples deklarative UI-Schicht (à la React). Sie kommt in diesem Projekt **nur als App-Entry** in `LunarLanderiOSApp.swift` vor; das Spiel selbst läuft im UIKit-`UIViewController`, weil eine vollflächige Metal-View viel einfacher imperativ aufgebaut wird.
- AppKit und UIKit unterscheiden sich um Größenordnungen (Event-Loops, Koordinatenursprung, Lebenszyklus). Deshalb gibt es zwei View-Controller, kein gemeinsamer.

---

## 3. Generelle Architektur des Spiels

### 3.1 Design-Entscheidungen

Folgende Entscheidungen prägen das Spiel; sie sind kein "Standard", aber im CLAUDE.md des Projekts und im Code klar erkennbar:

1. **Eine Renderer-Klasse für alles.**
   `Renderer.swift` enthält Metal-Pipeline, Spiellogik, Physik, Kollision, Partikelsystem, Textrendering und HUD. Bewusst monolithisch. Begründung im Repo: einfacher zu lesen, weniger Indirektion, in 2000 Zeilen noch handhabbar. Nicht refactoren, wenn du das Spiel verstehen willst.
2. **Plattform-Code lebt im View-Controller.**
   Input (Tastatur, Touch), Audio (`AVAudioPlayer`-Instanzen), App-Lifecycle. Der Renderer kennt nur *Booleans* (`thrustMain`, `thrustLeft`, `thrustRight`) und feuert *Callbacks* (`onStateChange`, `onFuelPickup`, `onLightPickup`). Das ist eine saubere Trennung; sie ist der Hauptgrund, warum Mac und iOS sich die ganze Spiel-Datei teilen können.
3. **Kein SpriteKit, kein SceneKit.**
   Alles wird per Hand in Vertex-Listen aufgebaut. Treiberseitig ist das *trivialer Code*: Drei Pipelines (Triangles, Lines/Strips, Points), ein Texture-Pipeline für Bitmap-Sprites. Stilistisch erinnert es an alte 80er-Vektor-Arcade-Spiele (Asteroids, Battlezone). Selbst der Font wird als Linien-Vektoren beschrieben — keine `NSAttributedString`, kein Core Text.
4. **Spielwelt in eigenen Koordinaten.**
   Intern arbeitet das Spiel auf einer Welt von `gameWidth = 1000` × `gameHeight ≈ 750`. Die Methode `gx`/`gy` mappt diese auf die `drawableSize` der View. Das macht das Spiel auflösungsunabhängig.
5. **Frame-rate-unabhängige Physik mit `dt`-Clamping.**
   Jede Update-Funktion bekommt ein `dt: Float`; `dt` wird auf `1/30` gedeckelt, damit das Spiel bei Frame-Drops nicht durch Wände tunnelt.
6. **Spielzustände als `enum GameState`.**
   Klassische FSM: `logo`, `highscores`, `demo`, `playing`, `landed`, `levelTransition`, `crashed`, `tippedOver`, `gameOver`, `enteringName`. Alle Übergänge laufen entweder zeitgetrieben (z. B. `gameTime - stateChangeTime >= 7.0`) oder eventgetrieben (Kollision, Tastendruck).
7. **Konfiguration in `GameConfig.swift`.**
   Spawn-Raten, Skalierungs-Multiplikatoren, Asset-Listen, Feature-Flags (Sound an/aus). Das ist die "Tweak-Schicht", die du anfassen darfst, ohne in `Renderer.swift` zu graben.

### 3.2 Funktionsblöcke

Das Spiel lässt sich in folgende Blöcke gliedern:

```
                       ┌──────────────────────────────┐
                       │       App-Lifecycle           │
                       │ (AppDelegate / SwiftUI App)  │
                       └──────────────┬───────────────┘
                                      │
                       ┌──────────────▼───────────────┐
                       │       View-Controller         │
                       │ (Input · Audio · UI-Buttons) │
                       └──────────┬─────────┬─────────┘
                                  │         │
                Callback (states) │         │ InputState (Booleans)
                                  │         ▼
                       ┌──────────▼──────────────────┐
                       │           Renderer           │
                       │  ┌────────┐  ┌────────────┐ │
                       │  │ Logik  │  │ Rendering   │ │
                       │  │ FSM,   │  │ Metal,      │ │
                       │  │ Physik │  │ Vertex-Bf., │ │
                       │  │ Spawn  │  │ Pipelines   │ │
                       │  └────┬───┘  └─────┬──────┘ │
                       │       │            │        │
                       │       ▼            ▼        │
                       │   GameConfig   ShaderTypes  │
                       │   HighscoreMgr  Shaders     │
                       └─────────────────────────────┘
                                  │
                            JSON-Datei  +  PNG/MP3 Assets
```

### 3.3 Zusammenspiel der Einheiten

**Boot-Sequenz (macOS):**

1. `@main AppDelegate` startet die NSApplication, lädt `Main.storyboard`. Das Storyboard instanziiert die `MTKView` als Wurzel und setzt `GameViewController` als deren ViewController.
2. `viewDidLoad()` holt `MTLCreateSystemDefaultDevice()`, baut `Renderer` und setzt sich als `delegate` der `MTKView`.
3. Die `MTKView` ruft fortan `mtkView(_, drawableSizeWillChange:)` und `draw(in:)` ~60-mal pro Sekunde auf — beides Delegate-Methoden im Renderer.
4. `GameViewController` registriert `NSEvent.addLocalMonitorForEvents` als globalen Key-Hook und mappt `Space`, `←`, `→` auf `renderer.input.*`.

**Boot-Sequenz (iOS):**

1. `@main LunarLanderiOSApp` (SwiftUI) öffnet ein `WindowGroup` mit `GameViewControllerRepresentable`, das den UIKit-`iOSGameViewController` wrappt.
2. Im `viewDidLoad()` wird die `MTKView` programmatisch erstellt, dem View hinzugefügt, `Renderer` initialisiert und als Delegate gesetzt.
3. Drei `UIButton` (Thrust, Links, Rechts) werden mit `addTarget(_, action:, for: .touchDown / .touchUpInside …)` an Bool-Setter angebunden.
4. Tap-Gesten und Name-Entry werden über `UITapGestureRecognizer` und `UITextField` realisiert.

**Frame-Loop (gemeinsam):**

```
draw(in:) [60 Hz]
   ├── update(dt:)
   │     ├── updateScorePopups
   │     ├── FSM-Switch (logo/highscores/demo/playing/landed/...)
   │     ├── updatePlaying(dt:)   ← nur im Spiel
   │     │     ├── velocityY -= gravity * dt
   │     │     ├── Thrust-Input → velocityY/X, Treibstoff, spawnThrustParticles
   │     │     ├── Atmosphären-Drag, Windkraft, Wind-Variation
   │     │     ├── Welt-Wrap-Around an X-Rändern
   │     │     ├── checkCollision (Boden / Pad / Tipping)
   │     │     ├── updateFloatingObjects + checkFloatingCollisions
   │     │     └── updateParticles
   │     └── ggf. State-Transitions (z. B. landed → levelTransition nach 1.5 s)
   ├── Render-Pass öffnen, Sky-Color aus Level wählen
   ├── Switch auf gameState → ruft `drawXxx`-Funktionen
   └── enc.endEncoding · present · commit
```

**Audio-Update** läuft im View-Controller und reagiert per Callback (`onStateChange`) auf Renderer-Übergänge sowie alle 250 ms per `Timer`, um Wind- und Engine-Loops sauber nachzuziehen.

---

## 4. Details — der Code im Einzelnen

### 4.1 Swift-Crashkurs für C/C++/Java-Veteranen

Bevor wir Datei für Datei gehen, hier die Swift-Konzepte, die im Code dauernd vorkommen — komprimiert auf das Wesentliche.

#### 4.1.1 Typen, `let` vs. `var`

```swift
let mainThrustPower: Float = 3.5        // Konstante (immutable binding)
var fuel: Float = 0                     // Variable
```

`let` ist *immutable* (wie `final` in Java oder `const` in C++). Bevorzugt verwenden. Typen werden inferiert, wenn der Initializer eindeutig ist; explizite Annotation (`: Float`) hilft, wenn man literal-Defaults nicht mit `Double` verwechseln will.

#### 4.1.2 Wert vs. Referenz

- `struct` und `enum` sind **Value Types** (per-Copy, stack-allokiert wenn möglich).
- `class` ist **Reference Type** (ARC, heap).
- Im Projekt: `Particle`, `Star`, `FloatingObject`, `Vertex2D`, `InputState` sind `struct`. `Renderer`, `HighscoreManager` sind `class`. Das ist die idiomatische Aufteilung: "Daten" als Struct, "Identität / Lebenszyklus" als Class.

#### 4.1.3 Optionals

```swift
var logoTexture: MTLTexture?    // entweder MTLTexture-Wert oder nil
guard let url = Bundle.main.url(forResource: "Logo", withExtension: "png") else { return }
```

`T?` ist syntaktischer Zucker für `Optional<T>`. Auspacken via `if let`, `guard let`, `??` (Nil-Coalescing), `!` (Force-Unwrap; im Code-Style verpönt, aber gelegentlich nötig).
`guard` ist wie `if !cond { exit-scope } else …` — der Else-Zweig **muss** den umgebenden Scope verlassen.

#### 4.1.4 Closures und `[weak self]`

```swift
renderer.onFuelPickup = { [weak self] in
    guard let self = self else { return }
    self.successPlayer?.play()
}
```

Closures sind first-class. `[weak self]` ist eine *Capture List*, die `self` als `weak` (schwach, ARC-frei) einfängt. Hier nötig, weil der Renderer das Closure speichert und sonst einen Retain-Zyklus mit dem View-Controller bauen würde.

#### 4.1.5 `enum` mit Methoden, ohne Werte und mit Assoziierten Daten

```swift
enum GameState { case logo, highscores, demo, playing, /* … */ }
enum FloatingObjectType { case light, heavy, fuel }
enum ThrustDirection { case main, left, right }
```

Swift-`enum`s sind echte algebraische Typen. Hier nur als reine Tag-Aufzählungen verwendet, aber sie können Methoden, Generics und assoziierte Werte (`case loaded(MTLTexture)`) tragen.

#### 4.1.6 Generics und Tuples

```swift
func loadFloatingTextures(_ entries: [(filename: String, bonus: Int)],
                          maxSize s: Int) -> [(MTLTexture, Int)]
```

Tupel mit Labels (`(filename:, bonus:)`) sind handlich für leichte Datenstrukturen. Das hätte ein eigener Struct sein können, aber Tupel halten den Code knapp. Externes Label `_` (für `entries`) und internes Label `maxSize s` (Aufrufer schreibt `maxSize:`, Funktion arbeitet mit `s`) — typisches Swift-Pattern für lesbare Call-Sites.

#### 4.1.7 Pattern-Matching im `switch`

```swift
switch state {
case .logo, .highscores:
    // …
case .crashed, .tippedOver:
    // …
default:
    break
}
```

`switch` ist **exhaustiv** für `enum`s — der Compiler zwingt dich, alle Fälle zu behandeln oder ein `default:` zu setzen. Es gibt keinen Fall-Through wie in C.

#### 4.1.8 Strings, Characters, Unicode

```swift
for char in text.uppercased() { /* char ist Character, nicht Byte */ }
```

`Character` ist eine **Grapheme-Cluster** — z. B. `é` als Kombi aus `e` + Akzent ist *ein* `Character`. Für unser Vektor-Font reicht ASCII; der Switch in `charSegs(_:)` listet die Glyphen direkt auf. Mit String-Subskripten arbeitet man über `String.Index`, nicht Int — Swift will keine illegalen Mid-Codepoint-Zugriffe.

#### 4.1.9 SIMD und C-Interop

```swift
var u = Uniforms2D(viewportSize: drawableSize)   // drawableSize: SIMD2<Float>
```

`SIMD2<Float>`, `SIMD4<Float>` haben **identisches Memory-Layout** zu Metals `float2`, `float4`. Das ist das Geheimrezept hinter `ShaderTypes.h`: die Typen sind C-Typen, beide Compiler verstehen sie binärkompatibel.

#### 4.1.10 Memory-Management bei `MTLBuffer`

`MTLBuffer.contents()` liefert einen `UnsafeMutableRawPointer` (≙ `void*`). Wir kopieren mit `memcpy` (aus libc). Swift hat hier keine Magie — das ist nackte Zeigerarithmetik, eingerahmt von `vertexBufferOffset`-Bookkeeping.

---

### 4.2 `ShaderTypes.h` — die Brücke zwischen CPU und GPU

```c
typedef struct {
    vector_float2 position;
    vector_float4 color;
} Vertex2D;
```

Trick: Die Datei wird *sowohl* in Swift (über den Bridging-Header, den Xcode automatisch ableitet, weil `ShaderTypes.h` im Bundle-Target liegt) *als auch* in `Shaders.metal` (`#import "ShaderTypes.h"`) eingelesen. Auf CPU-Seite ist `vector_float2` ein typedef auf `simd_float2`, das in Swift als `SIMD2<Float>` auftaucht. Auf GPU-Seite ist `vector_float2` schlicht `float2`.

Das löst ein hartes Problem klassischer Pipeline-Programmierung: **wie sorge ich dafür, dass CPU-Layout und GPU-Layout exakt übereinstimmen, ohne sie zweimal zu pflegen?** Antwort: Eine `.h`-Datei, ein Compiler-Frontend-Trick.

Vergleichbares aus deiner Welt: OpenGL-Apps, die Headerdateien zwischen GLSL und C++ teilen, indem sie GLSL-#defines manuell nachziehen. Apple hat es offiziell gelöst.

Die `#ifdef __METAL_VERSION__`-Macros erlauben Plattform-Spezifika (Metal kennt `NSEnum`-artige Enums nur über ein Macro).

---

### 4.3 `GameConfig.swift` — zentrale Konfiguration

```swift
struct GameConfig {
    static let cheatLevelSelectEnabled: Bool = true
    static let attractMusicEnabled: Bool = true
    static let gameplayMusicEnabled: Bool = false
    // ...
    struct FloatingObjectClassConfig {
        let spawnsPerSecond: Float
        let spawnLevelMultiplier: Float
        let minInitialSpeed: Float
        let maxInitialSpeed: Float
        let speedLevelMultiplier: Float
    }
    static let lightObject = FloatingObjectClassConfig(/* … */)
    static let heavyObject = FloatingObjectClassConfig(/* … */)
    static let fuelObject  = FloatingObjectClassConfig(/* … */)
    static func floatingConfig(for type: FloatingObjectType) -> FloatingObjectClassConfig { … }
    static let lightObjects: [(filename: String, bonus: Int)] = [ … ]
    static let heavyObjects: [(filename: String, bonus: Int)] = [ … ]
    static let fuelObjects:  [(filename: String, bonus: Int)] = [ … ]
    static let lightObjectMaxSize: Int = 150/4
    /* … */
}
```

Bemerkenswertes:

- **`struct` als Namespace.** Da Swift keinen `namespace`-Mechanismus hat, ist das idiomatische Pattern, statische Konstanten in einen leeren `struct` zu legen.
- **Spawn-Formel: `rate = spawnsPerSecond × spawnLevelMultiplier × level`.** Das gibt einen sauberen "wie sehr eskaliert das mit dem Level"-Hebel. Mehr dazu in `tickRandomSpawning`.
- **Pixmap-Liste als Tupel-Array.** Die Bonus-Zahl wandert mit der Datei mit, nicht über Map-Lookups. Einfach, lokal, gut.
- **`/4`-Anmerkung:** Im Repo wird explizit kommentiert, dass das Hand-tuning ist und nicht angerührt werden soll. Solche Hinweise gehören in Konfigurationsdateien.

**Erweiterung:** Das CLAUDE.md erwähnt, dass per-Level-Pools (z. B. Meteoriten nur auf äußeren Welten) noch fehlen. Der Funktionsschnitt `floatingConfig(for:)` zeigt schon den Hebel, wo das ansetzen würde: man würde `texturePool(for:)` (siehe Renderer) zusätzlich vom `currentLevel` abhängig machen.

---

### 4.4 `HighscoreManager.swift` — Persistenz mit `Codable`

```swift
struct HighscoreEntry: Codable { let name: String; let score: Int; let level: Int }
struct HighscoreTable: Codable { var entries: [HighscoreEntry]; /* … */ }

class HighscoreManager {
    static let shared = HighscoreManager()
    private let directoryPath: String
    private let filePath: String
    var table: HighscoreTable
    /* … */
}
```

Konzepte hier:

- **`Codable`** ist Swifts JSON-/PList-Serialisierungs-Protokoll. Compiler synthetisiert Encode/Decode-Methoden für alle Properties, wenn alle ihrerseits `Codable` sind. Das ist *enorm* viel besser als Java/Jackson-Annotations-Hölle.
- **`JSONEncoder().encode(table)`** und `JSONDecoder().decode(HighscoreTable.self, from: data)` sind alles, was du brauchst. `.self` ist ein Type-Reference-Literal (`HighscoreTable.self : HighscoreTable.Type`).
- **Singleton via `static let shared`.** In Swift sind `static let`-Initializer thread-safe und lazy — du bekommst quasi gratis einen sicheren Singleton.
- **Plattform-Pfad.** macOS legt unter `~/.lunarlander/`, iOS unter `Documents/LunarLander/`. Die `#if os(iOS) … #else … #endif`-Direktive ist eine *Compile-Time*-Bedingung (im Gegensatz zu Runtime-Plattform-Switches in C#).
- **`mutating func insert(_:)`** auf einem `struct` — Swift verlangt diese Annotation, weil das Aufrufen einer mutierenden Methode auf einer `let`-Variable verboten ist. Schicker Trick: der Compiler weiß zur Compile-Zeit, ob du eine Methode auf eine Konstante anwendest.

---

### 4.5 `AppDelegate.swift` und der macOS-Lifecycle

Sehr kurz; klassisch AppKit:

```swift
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!
    func applicationDidFinishLaunching(_ aNotification: Notification) {}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```

- `@main` markiert die Klasse als Programmstart. Der Compiler generiert `main()`.
- `@IBOutlet` ist die "von der Storyboard-Datei wird beim Laden ein Pointer eingesetzt"-Annotation. Force-Unwrapped (`!`), weil Storyboard das Setzen garantiert.
- Der Code ist absichtlich leer — alles Wichtige passiert im View-Controller. AppKit erwartet aber, dass das `NSApplicationDelegate` existiert.
- `applicationShouldTerminateAfterLastWindowClosed → true` macht das App-Verhalten gleich wie ein normales Tool: Fenster zu = Programm zu. (Mac-Standard wäre, dass die App im Dock weiterläuft.)

---

### 4.6 `GameViewController.swift` (macOS) — Input, Audio, Lifecycle

Dies ist die Vermittler-Schicht zwischen AppKit und Renderer. Ihre Aufgaben:

1. **Metal initialisieren.**
   ```swift
   guard let defaultDevice = MTLCreateSystemDefaultDevice() else { … }
   mtkView.device = defaultDevice
   ```
   `MTLCreateSystemDefaultDevice()` liefert die GPU (auf Apple Silicon: integrated; auf alten Intel-Macs: discrete oder integrated, je nach System).

2. **Renderer als View-Delegate registrieren.**
   `MTKView` ruft `delegate.draw(in:)` und `delegate.mtkView(_:, drawableSizeWillChange:)` auf. Der Renderer implementiert das `MTKViewDelegate`-Protokoll.

3. **Audio aufsetzen.**
   `AVAudioPlayer` wird für die Hintergrundmusik (`Lunar Descent Loop.mp3`), Engine-Loop, Wind-Loops, Crash-, Success- und Blurp-Effekte vorgehalten. Die Player werden via `numberOfLoops = -1` auf Endlosschleife gestellt, `volume` und `prepareToPlay()` (decodiert Audio in den Speicher, damit `play()` keine Latenz hat).

4. **Auf Renderer-States reagieren.**
   ```swift
   renderer.onStateChange = { [weak self] state in
       switch state {
       case .logo, .highscores: self.startMusic(); self.stopAllGameSounds()
       case .playing: …
       case .crashed, .tippedOver: …
       }
   }
   ```
   Das ist die zentrale Kopplung. Der Renderer ruft `onStateChange?(.playing)`, der ViewController reagiert mit Audio.

5. **Globale Tastatur-Hooks.**
   ```swift
   keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in …; return event }
   ```
   `addLocalMonitorForEvents` ist die robuste Variante zu Responder-Chain-basiertem Keyboard-Handling. Der Closure liefert `nil` zurück, wenn das Event *konsumiert* werden soll (sonst piept der Mac bei nicht behandelten Tasten).

   Die Schlüsselcodes sind reine Hardware-Codes (`49 = Space`, `123 = Left Arrow`, …), nicht Unicode. Das ist robuster, weil sie nicht von Tastatur-Layouts abhängen.

6. **State-spezifisches Input-Routing.**
   - In `.enteringName` werden alle Tasten konsumiert, Buchstaben gehen an `renderer.appendNameCharacter(_:)`.
   - In `.playing` werden Tastendrücke und -loslassen an `renderer.input` weitergegeben.
   - In `.crashed`/`.tippedOver` und mit `lives > 0` plus 600-ms-Cooldown wird `retryCurrentLevel()` getriggert.
   - In `.logo`/`.highscores`/`.demo` startet `R` ein neues Spiel; `1`-`9` springen direkt zu einem Level (Cheat-Modus).

7. **Wind-Audio nachziehen.**
   `Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true)` poked `updateWindSound()` und `updateEngineSound()`. Damit überspielt der ViewController auch *Demo-Modus*-Sounds, in dem der Renderer keine Key-Up-Events sendet.

   Drei Wind-Files (`wind_01_low`, `wind_02_gusyt`, `wind_03_high`) werden je nach `|windForce|` gewechselt, Lautstärke kontinuierlich gemappt.

8. **`deinit`-Cleanup.**
   `windUpdateTimer?.invalidate()` und `NSEvent.removeMonitor(monitor)` müssen ausgeführt werden, sonst leakt der Closure-Capture-Graph.

**Wichtiger Style-Punkt:** Der ViewController kennt `GameConfig.soundEffectsEnabled` und `GameConfig.gameplayMusicEnabled` — Feature-Flags werden also dort konsumiert, wo das Side-Effect lebt. Saubere Praxis.

---

### 4.7 `LunarLanderiOSApp.swift` — SwiftUI als App-Entry

```swift
@main
struct LunarLanderiOSApp: App {
    var body: some Scene {
        WindowGroup {
            GameViewControllerRepresentable()
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct GameViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> iOSGameViewController { iOSGameViewController() }
    func updateUIViewController(_ uiViewController: iOSGameViewController, context: Context) {}
}
```

Drei Konzepte für Neueinsteiger:

- **`App` und `Scene` Protokolle.** SwiftUI-App-Definitionen sind Werttypen, die ein `body` ableiten. Eine *Scene* ist eine Fenster-/Lebenszyklus-Einheit, ein `WindowGroup` eine Sammlung typgleicher Fenster.
- **`some Scene`** ist *opaque return type*. Bedeutet: "der konkrete Typ wird vom Compiler ausgerechnet, der Aufrufer weiß nur, dass er irgendein `Scene` ist". Ähnlich `auto` in C++.
- **`UIViewControllerRepresentable`** ist die Brücke aus SwiftUI in UIKit. Wir bauen die ganze App imperativ und nutzen SwiftUI nur als Halter.
- **`.ignoresSafeArea()`, `.statusBarHidden()`, `.persistentSystemOverlays(.hidden)`** sind View-Modifier — Methodenketten, die einen neuen `View` wrappen. Hier sorgen sie für echtes Vollbild ohne Statusbar.

---

### 4.8 `iOSGameViewController.swift` — UIKit-Einbettung

Sehr ähnlich zum Mac-Pendant, aber mit:

- **Programmatischer View-Aufbau** (`mtkView = MTKView(frame: view.bounds)`) — kein Storyboard.
- **`AVAudioSession.setCategory(.ambient, …)`** — iOS verlangt eine explizite Audio-Session-Konfiguration (Ambient = mische dich mit System-Sound, pausiere bei Silent Switch).
- **Drei `UIButton`s** als Touch-Controls, alpha=0.35 für "kaum sichtbar, aber tappbar".
- **`addTarget(_, action: #selector(thrustDown), for: .touchDown)`** — Objective-C-Selector-Mechanik. `#selector` ist eine compiler-validierte Referenz auf eine `@objc`-Methode.
- **`UITextField`** für die Namenseingabe — bei iOS deutlich einfacher als ein eigener Soft-Keyboard-Aufruf.
- **`UITapGestureRecognizer`** für Tap-to-Start in den Attract-Screens.
- **`DispatchQueue.main.async { … }`** in Renderer-Callbacks: AVAudioPlayer und UIKit-API müssen vom Main Thread aus aufgerufen werden. Der Renderer ruft seine Callbacks aus dem Render-Thread — also Aufruf in die Main Queue dispatchen.

Genau das ist auf macOS nicht so streng nötig, weil dort die `MTKView` ebenfalls auf der Main Queue zeichnet. Auf iOS *kann* aber MetalKit, abhängig von Konfiguration, auch auf einem anderen Thread laufen, weshalb der iOS-VC defensiver ist.

---

### 4.9 `Renderer.swift` — das Herz des Spiels

Wir gehen `Renderer.swift` nun in **logische Abschnitte** durch. Die Zeilennummern beziehen sich auf den vorliegenden Codestand.

#### 4.9.1 Datenstrukturen (Zeilen ~14–91)

```swift
private let mainThrustPower: Float = 3.5
private let mainFuelRate: Float = 8.0
private let maxLandingVSpeed: Float = 2.5
// ...

enum GameState { case logo, highscores, demo, playing, landed, levelTransition, crashed, tippedOver, gameOver, enteringName }
struct InputState { var thrustMain: Bool = false; var thrustLeft: Bool = false; var thrustRight: Bool = false }
struct Particle { var x: Float; var y: Float; var vx: Float; var vy: Float; var life: Float; var maxLife: Float; var r,g,b: Float }
struct Star { var x: Float; var y: Float; var brightness: Float; var twinkleSpeed: Float; var twinklePhase: Float }
enum FloatingObjectType { case light, heavy, fuel }
struct FloatingObject { /* Typ, Texture, Position, Rotation, Velocity */ }
struct ScorePopup { var x, y: Float; var text: String; var life: Float; let maxLife: Float }
```

Reine Daten, alles `struct`. Das ist wichtig: Wenn du in einer Schleife `for i in floatingObjects.indices` schreibst und über `floatingObjects[i]` mutierst, weiß Swift, dass das Array eine *Value*-Modifikation ist — kein Cross-Thread-Problem.

#### 4.9.2 Renderer-Klasse: Eigenschaften (Zeilen ~95–211)

Highlights:

```swift
let gameWidth: Float = 1000.0
var gameHeight: Float = 750.0
var pixelsPerMeter: Float = 12.0
var drawableSize: SIMD2<Float> = SIMD2<Float>(800, 600)
```

`gameWidth` ist *konstant* (`let`), `gameHeight` und `drawableSize` werden in `mtkView(_, drawableSizeWillChange:)` anhand des Aspect-Ratios neu berechnet. Das ist die Auflösungsunabhängigkeit.

```swift
var vertexBuffer: MTLBuffer!
let maxVertices = 131072
var vertexBufferOffset = 0
```

Ein einziger großer `MTLBuffer` (≈ 4 MB für `Vertex2D`) wird pro Frame als linearer Allokator benutzt: Bei jedem `upload(...)` wird in den Offset hineinkopiert, der Offset hochgezogen. Das vermeidet das andauernde Erzeugen kleiner Buffers (ein klassisches Apple-/OpenGL-Antipattern wäre das hier).

```swift
var onStateChange: ((GameState) -> Void)?
var onFuelPickup: (() -> Void)?
var onLightPickup: (() -> Void)?
```

Reine Funktionsreferenzen — das ist die Entkopplungsschicht zum View-Controller. Optional, damit der Renderer auch ohne Host (z. B. in Tests) lauffähig wäre.

#### 4.9.3 Initialisierung (Zeilen ~213–271)

```swift
@MainActor
init?(metalKitView: MTKView) {
    self.device = metalKitView.device!
    self.commandQueue = self.device.makeCommandQueue()!
    super.init()
    metalKitView.colorPixelFormat = .bgra8Unorm_srgb
    metalKitView.depthStencilPixelFormat = .invalid
    metalKitView.preferredFramesPerSecond = 60
    guard let library = device.makeDefaultLibrary() else { return nil }
    ...
}
```

- **`@MainActor`** ist eine Swift-Concurrency-Annotation. Sie zwingt den Initializer, auf der Main-Queue (Main-Thread) zu laufen. Notwendig, weil `MTKView` ein UI-Objekt ist.
- **`init?`** ist ein *failable initializer*. Wenn Setup fehlschlägt (z. B. Library nicht ladbar), gibt er `nil` zurück. Das Aufrufer-Idiom: `guard let r = Renderer(metalKitView: mtkView) else { print("nope") }`.
- **`makeDefaultLibrary()`** lädt die per Xcode-Build geshipped Metal-Library (alle `.metal`-Dateien werden zu *einer* Library kompiliert).
- **Pipelines** werden für Triangle, Line und Point-Topology angelegt — alle drei nutzen denselben Vertex-Shader (`vertexShader2D`), aber unterschiedliche Fragment-Shader (`fragmentShader2D` für Triangles/Lines, `starFragmentShader` für Points).
- **Blending** ist konfiguriert auf `sourceAlpha`/`oneMinusSourceAlpha` — Standard-Alpha-Blending.
- **Texture-Pipeline** ist die vierte Pipeline für textured Quads (Logo, Floating Objects).

#### 4.9.4 Asset-Loading (Zeilen ~273–349)

```swift
func loadLogoTexture() { … }                 // MTKTextureLoader, einfach
func loadFloatingTextures(_ entries:, maxSize s:) -> [(MTLTexture, Int)] { … }
private func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? { … }
```

Drei Erkenntnisse:

1. **`MTKTextureLoader`** abstrahiert das ganze PNG → GPU-Format-Geraffel weg. Optionen: `.SRGB: true`, `.origin: .topLeft` (Y-Konvention auf Texture-Seite).
2. **Pixmap-Downsampling** läuft über `CGImageSource` + `CGContext`. Das ist die Apple-Variante von "PIL.resize". `bytesPerRow: width * 4`, `bitsPerComponent: 8`, `premultipliedLast` — Standard-RGBA.
3. **Datei nicht gefunden?** Wird mit `print(...)` geloggt und übersprungen. Nicht crashen.

#### 4.9.5 Level-Setup und Physik (Zeilen ~351–534)

`startNewGame()`, `startGameAtLevel(_:)`, `setupNextLevel()`, `setupLevel()`, `configureLevelPhysics()`.

`setupLevel()` ist besonders interessant — es berechnet **vor** dem Spielstart, wie viel Treibstoff der Spieler braucht:

```swift
let fallDistance = (landerY - landingPadY - landerH / 2.0 - legHeight) / pixelsPerMeter
let horizontalDistance = abs(landerX - padCenter) / pixelsPerMeter
let fallTime = sqrt(2.0 * max(fallDistance, 1) / levelGravity)
let impactVelocity = levelGravity * fallTime
let verticalBurnTime = impactVelocity / (levelMainThrust - levelGravity)
let verticalFuel = verticalBurnTime * mainFuelRate
let hTime = sqrt(2.0 * max(horizontalDistance, 1) / levelSideThrust)
let horizontalFuel = hTime * sideFuelRate * 2.0
let windFuel = abs(windBase) * fallTime * sideFuelRate * 0.5
let fuelMultiplier = max(1.2, 1.6 - Float(currentLevel - 1) * 0.1)
initialFuel = (verticalFuel + horizontalFuel + windFuel) * fuelMultiplier
```

Das ist klassische *Tank-as-Function-of-Difficulty*-Mathematik:

- Freier-Fall-Zeit aus `s = ½·a·t² → t = √(2s/a)`.
- Aufprall-Geschwindigkeit `v = a·t`.
- Brennzeit, um diese Geschwindigkeit gegen Nettoschub `levelMainThrust − levelGravity` auszubremsen.
- Horizontal: doppelter Faktor, weil Reisen + Bremsen.
- Wind: pauschal `0.5 ·` Basis-Wind über die Fallzeit gegenrudern.
- Multiplikator startet bei 1.6 (Level 1), runter auf 1.2 (Level 5+). Höhere Levels = enger.

Das macht das Spiel *fair*: Auch im härtesten Level reicht der Tank theoretisch, wenn man optimal fliegt.

`configureLevelPhysics()` setzt zudem `skyColor`, `terrainSurface`, `terrainDeep`, `terrainOutline` als Tupel je Level. Schöner Vektor-Look, kein Texture-Mapping nötig.

#### 4.9.6 Scoring (`calculateLevelScore`, Zeilen 538–548)

```swift
let fuelPercent = fuel / max(initialFuel, 1.0)
let fuelBonus = fuelPercent * 500.0
let vFactor = 1.0 - (min(abs(velocityY), maxLandingVSpeed) / maxLandingVSpeed)
let vBonus = vFactor * 300.0
// ...
let multiplier = 1.0 + Float(currentLevel - 1) * 0.2
return Int((base + fuelBonus + vBonus + hBonus) * multiplier)
```

Klassische **gewichtete Summe**: Treibstoffrest, sanfte Vertikalrate, sanfte Horizontalrate, dazu ein per-Level-Multiplikator (Level 5 = 1.8×). Solche additiven Score-Formeln sind aus Game-Design-Sicht okay, weil der Spieler an jedem Hebel etwas verbessern kann.

#### 4.9.7 Terrain-Generation (Zeilen ~573–621)

```swift
let numSegments = 80
let baseH = gameHeight * 0.18
let maxVar = gameHeight * 0.22

let padSegStart = Int.random(in: 10...(numSegments - 15))
let padSegEnd = padSegStart + 5

for i in 0...numSegments {
    if i >= padSegStart && i <= padSegEnd { heights.append(0) }
    else {
        let n = Float(i) / Float(numSegments)
        let v1 = sin(n * .pi * 2.3) * maxVar * 0.35
        let v2 = sin(n * .pi * 5.7) * maxVar * 0.25
        let v3 = sin(n * .pi * 11.3) * maxVar * 0.15
        let rnd = Float.random(in: -maxVar * 0.12 ... maxVar * 0.12)
        heights.append(baseH + v1 + v2 + v3 + rnd)
    }
}
```

Drei überlagerte Sinus-Wellen mit unterschiedlichen Frequenzen + Rauschen → fraktal-anmutende Skyline. Die Pad-Höhe wird auf `min(left, right) * 0.9` gesetzt, dann werden die drei Pixel links/rechts der Plattform in einem linearen Lerp angeglichen, damit der Übergang nicht zackig wirkt. Solider Standard.

Vergleich zur Heightmap-Welt: Hier ist es **1D** statt 2D, weil wir ein 2D-Side-Scroller-Spiel haben. Sonst dasselbe Prinzip.

#### 4.9.8 Game-Update / FSM (Zeilen ~638–809)

`update(dt:)` ist die Wurzel-Update-Funktion. Sie ruft je nach State `updatePlaying`, `updateParticles`, etc., und steuert Auto-Transitions per `gameTime - stateChangeTime`.

`updatePlaying(dt:)` ist die Physik-Engine:

```swift
velocityY -= levelGravity * dt
if input.thrustMain && fuel > 0 { velocityY += levelMainThrust * dt; fuel -= mainFuelRate * dt; … }
velocityX *= (1.0 - atmosphereDrag * dt)        // exponentielle Bremsung
velocityX += windForce * dt
if windVariability > 0 {
    windChangeTimer += dt
    if windChangeTimer >= 2.0 { windTargetForce = … }
    windForce += (windTargetForce - windForce) * dt * 0.8   // sanftes Ease zu Target
}
landerX += velocityX * pixelsPerMeter * dt
landerY += velocityY * pixelsPerMeter * dt
if landerX < 0 { landerX += gameWidth }                     // Wrap-Around
if landerX > gameWidth { landerX -= gameWidth }
checkCollision()
updateFloatingObjects(dt: dt)
checkFloatingCollisions()
updateParticles(dt: dt)
```

- **`velocity *= (1 - drag * dt)`** ist die Diskretisierung von `dv/dt = -drag·v` (einfaches Euler). Für die Spiel-Geschwindigkeit unproblematisch.
- **Wind-Smoothing:** `windForce += (target - windForce) * dt * 0.8` ist ein klassisches *Exponential Moving Average*. Macht Windänderungen weich.
- **Wrap-Around am X-Rand** statt unsichtbarer Wand — schöner Touch.

`updateDemoAI()` ist eine handgebastelte Bang-Bang-Regelung: Steuere horizontal Richtung Pad-Mitte, drossle Vertikalgeschwindigkeit nach Höhe. Drei Höhenzonen, drei Zielraten. Nichts Magisches; reicht, um die Demo nicht peinlich aussehen zu lassen.

#### 4.9.9 Partikelsystem (Zeilen ~811–877)

```swift
func spawnThrustParticles(direction: ThrustDirection, dt: Float) {
    let count = max(1, Int(dt * 150))   // 150 Partikel pro Sekunde
    for _ in 0..<count {
        var p = Particle(/* … gelb-orange, life 0.15–0.5 s, vy nach unten */)
        switch direction { case .main: …; case .left: …; case .right: … }
        particles.append(p)
    }
}

func updateParticles(dt: Float) {
    particles = particles.compactMap { p in
        var p = p
        p.life -= dt
        if p.life <= 0 { return nil }
        p.x += p.vx * dt
        p.y += p.vy * dt
        p.vy -= levelGravity * pixelsPerMeter * 0.3 * dt
        return p
    }
}
```

- **`compactMap`** ist Swifts "map+filter-nil"-Helfer. Du gibst aus dem Closure `nil` zurück, um das Element zu droppen.
- **Partikel haben eigene Gravitation** mit Faktor 0.3 — sieht hübsch aus, weil sie nicht so schnell fallen wie der Lander.
- **Render-Phase als Quads.** In `drawParticles` wird jedes Partikel zu *zwei Dreiecken* (2.5 px Halb-Breite). Es gäbe einen `pointPipeline`, aber Quads erlauben Alpha-Fade pro Vertex.
- **Stars vs. Particles:** Stars werden als *Points* mit dem `starFragmentShader` gerendert (kreisförmig dank `pointCoord`-Trick), Particles als Triangles. Konzeptionell unterschiedlich, kommt im Shader-Kapitel zurück.

#### 4.9.10 Kollisionserkennung (Zeilen ~881–927)

Sehr einfach, sehr robust:

```swift
let footY = landerY - landerH/2 - legHeight
let leftFoot = landerX - legSpread/2
let rightFoot = landerX + legSpread/2
let maxT = max(terrainHeightAt(x: landerX),
               terrainHeightAt(x: leftFoot),
               terrainHeightAt(x: rightFoot))
if footY <= maxT {
    let onPad = leftFoot >= landingPadStart && rightFoot <= landingPadEnd
    if onPad && |vY| ≤ 2.5 && |vX| ≤ 2.5 { → .landed }
    else if |vY| ≤ 2.5 && |vX| > 2.5     { → .tippedOver }
    else                                  { → .crashed }
}
if landerY < -50 { → .crashed }                   // unten rausgefallen
```

`terrainHeightAt(x:)` macht ein lineares Interpolieren zwischen den zwei umgebenden Terrain-Segmenten. Da Terrain als Polyline gespeichert ist (~80 Segmente, also ~12.5 m breit pro Segment in Game-Units), reicht das vollkommen.

Drei Endzustände — landed, tippedOver, crashed — sind nicht nur unterschiedliche Sound-Effekte, sondern auch unterschiedliche Animations- und Score-Pfade. Das ist ein Spielmechanik-Detail, das viele Klone übersehen.

#### 4.9.11 Floating Objects (Zeilen ~929–1097)

`spawnFloatingObjects()` initialisiert beim Level-Start ein paar Lichtobjekte mitten im Spielfeld, damit der Bildschirm nicht leer beginnt.

`spawnObject(of:atEdge:)` wählt eine zufällige Pixmap, einen zufälligen Y-Start, eine zufällige Rotation und Winkelgeschwindigkeit. Spawn am Rand oder im Inneren. Die Display-Größe wird *1:1* aus der Texture übernommen — d. h. ein 38-Pixel-Bild wird als 38-Game-Units-Quad gerendert. Pragmatisch, aber bedeutet: ändert man `lightObjectMaxSize`, ändert sich gleichzeitig Texturauflösung *und* Spielgröße.

`tickRandomSpawning(dt:)` ist die Spawn-Logik:

```swift
lightSpawnAccumulator += lc.spawnsPerSecond * lc.spawnLevelMultiplier * level * dt
while lightSpawnAccumulator >= 1.0 {
    spawnObject(of: .light, atEdge: true)
    lightSpawnAccumulator -= 1.0
}
```

Das **Accumulator-Pattern** garantiert eine zeit-exakte Rate, unabhängig von Frame-Spikes. Bei `fuel`-Objekten gilt zusätzlich "max 1 zur Zeit": Der Akkumulator wird auf `1.0` gehalten, bis das aktuelle Fuel-Object weg ist — so geht kein Spawn verloren, sondern wird *quasi gepuffert*.

`checkFloatingCollisions()` ist AABB mit `hitFactor = 0.6` (kleiner als gerendert, damit transparente Pixmap-Ecken nicht treffen):

```swift
case .heavy: → .crashed, lives -= 1, Explosion
case .fuel:  fuel = min(fuel + initialFuel * 0.4, initialFuel), onFuelPickup?()
case .light: totalScore += obj.bonus, ScorePopup, onLightPickup?()
```

Wertvolles Detail: `hitFactor: 0.6` ist eine wichtige *spielfühlung*-Konstante. Ohne sie würden die schwierigen Heavy-Objects unfair triggern.

#### 4.9.12 Draw-Loop (Zeilen ~1117–1209)

```swift
func draw(in view: MTKView) {
    let now = CACurrentMediaTime()
    let dt = lastUpdateTime == 0 ? 1/60 : Float(now - lastUpdateTime)
    lastUpdateTime = now
    update(dt: min(dt, 1.0/30.0))               // dt clamping
    ...
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: skyColor.r, …)
    let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
    vertexBufferOffset = 0                       // Linear Allocator reset
    var u = Uniforms2D(viewportSize: drawableSize)

    switch gameState {
    case .logo:   drawStars(...); drawLogo(...)
    case .playing: drawStars; drawTerrain; drawLandingPad; drawParticles; drawLander; drawHUD
    ...
    }

    enc.endEncoding()
    if let drawable = view.currentDrawable { commandBuffer.present(drawable) }
    commandBuffer.commit()
}
```

Eine ganz klassische **Begin-Encode-Present-Commit**-Sequenz. Jeder State-Branch listet die Layer von hinten nach vorn (Sky → Sterne → Terrain → Pad → Partikel → Lander → HUD → Overlay).

#### 4.9.13 Upload-Helper (Zeilen ~1216–1240)

```swift
func upload(encoder: MTLRenderCommandEncoder, vertices: [Vertex2D],
            uniforms: inout Uniforms2D, type: MTLPrimitiveType) {
    let byteSize = vertices.count * MemoryLayout<Vertex2D>.stride
    guard vertexBufferOffset + byteSize <= totalBufferSize else { return }
    memcpy(vertexBuffer.contents() + vertexBufferOffset, vertices, byteSize)
    switch type {
    case .point: encoder.setRenderPipelineState(pointPipeline)
    case .line, .lineStrip: encoder.setRenderPipelineState(linePipeline)
    default: encoder.setRenderPipelineState(trianglePipeline)
    }
    encoder.setVertexBuffer(vertexBuffer, offset: vertexBufferOffset, index: 0)
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms2D>.stride, index: 1)
    encoder.drawPrimitives(type: type, vertexStart: 0, vertexCount: vertices.count)
    vertexBufferOffset += byteSize
}
```

- `setVertexBytes(_:length:index:)` für kleine (<4 KB) Uniforms ist effizienter als ein eigener `MTLBuffer`.
- Pro Draw eine Pipeline auswählen, Buffer + Offset binden, drawen, Offset hochziehen. Klassischer Single-Pass-Linear-Allocator.

#### 4.9.14 Vektor-Font (Zeilen ~1983–2053)

```swift
func drawText(_ text: String, x: Float, y: Float, scale: Float, r,g,b: Float, enc: …, u: inout …) {
    var lines: [Vertex2D] = []
    var cx = x
    for char in text.uppercased() {
        for seg in charSegs(char) {
            lines.append(v(cx + seg.0 * scale, y + seg.1 * scale, r,g,b))
            lines.append(v(cx + seg.2 * scale, y + seg.3 * scale, r,g,b))
        }
        cx += 7.0 * scale
    }
    upload(encoder: enc, vertices: lines, uniforms: &u, type: .line)
}

func charSegs(_ c: Character) -> [(Float, Float, Float, Float)] {
    switch c {
    case "A": return [(0,0,w/2,h),(w/2,h,w,0),(w*0.2,m*0.8,w*0.8,m*0.8)]
    case "B": return [(0,0,0,h),...]
    ...
    }
}
```

Jeder Glyph ist eine Liste von **Liniensegmenten** `(x0,y0,x1,y1)`. Das ergibt einen Computer-/Arcade-Look (Asteroids-Font), ist trivial skalierbar und braucht **keine Font-Engine**. Nachteil: nur ASCII großgeschrieben, kein Kerning, kein Anti-Aliasing.

Die `7.0 * scale`-Vorschubweite ist auch der Faktor, mit dem überall im Code die Text-Breite pre-berechnet wird, um z. B. `cx - textW/2` zu zentrieren.

---

## 5. Metal Shaders — `Shaders.metal` im Detail

```cpp
typedef struct {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
} RasterizerData;

vertex RasterizerData vertexShader2D(uint vertexID [[vertex_id]],
                                     constant Vertex2D *vertices [[buffer(0)]],
                                     constant Uniforms2D &uniforms [[buffer(1)]]) {
    RasterizerData out;
    float2 pixelPos = vertices[vertexID].position;
    float2 clipPos = (pixelPos / (uniforms.viewportSize / 2.0)) - 1.0;
    out.position = float4(clipPos.x, clipPos.y, 0.0, 1.0);
    out.color = vertices[vertexID].color;
    out.pointSize = 3.0;
    return out;
}

fragment float4 fragmentShader2D(RasterizerData in [[stage_in]]) {
    return in.color;
}

fragment float4 starFragmentShader(RasterizerData in [[stage_in]],
                                    float2 pointCoord [[point_coord]]) {
    float2 center = pointCoord - float2(0.5);
    float dist = length(center);
    if (dist > 0.5) discard_fragment();
    float alpha = 1.0 - smoothstep(0.0, 0.5, dist);
    return float4(in.color.rgb, in.color.a * alpha);
}
```

### 5.1 Metal Shading Language in Kürze

MSL ist eine C++14-Untermenge mit:

- **Attributen in doppelten eckigen Klammern** (`[[position]]`, `[[buffer(0)]]`, `[[vertex_id]]`, `[[stage_in]]`, `[[point_coord]]`) — eine Erweiterung der C++-Syntax, vergleichbar mit Microsoft `__attribute__`/HLSL `: SV_POSITION`.
- **Stage-Qualifiern** vor Funktionen (`vertex`, `fragment`, `kernel`).
- **Adress-Space-Qualifiern** (`constant`, `device`, `threadgroup`).

### 5.2 Vertex-Shader

```cpp
vertex RasterizerData vertexShader2D(uint vertexID [[vertex_id]],
                                     constant Vertex2D *vertices [[buffer(0)]],
                                     constant Uniforms2D &uniforms [[buffer(1)]]) {
```

- **`vertex_id`** ist eine vom Rasterizer gestellte 32-Bit-ID. Die Funktion läuft *einmal pro Vertex*.
- **`buffer(0)`** und **`buffer(1)`** sind die Slot-IDs, die im Swift-Code via `setVertexBuffer(buffer, offset:, index: 0)` und `setVertexBytes(&u, length:, index: 1)` belegt werden. *Slot-Nummerierung muss exakt übereinstimmen* — sonst undefiniertes Verhalten.
- **Pipeline:**
  1. Pixel-Position aus dem Vertex-Buffer lesen.
  2. Auf Clip-Space (-1..1, -1..1) skalieren: `(pixel / (size/2)) - 1`.
  3. Z=0 (2D), W=1 (perspektivische Division neutral).
  4. Farbe durchreichen.
  5. Punktgröße auf 3 px setzen — wird vom Rasterizer nur für `MTLPrimitiveType.point` benutzt.

### 5.3 Fragment-Shader

- **`fragmentShader2D`** ist trivial: gib einfach die interpolierte Farbe zurück. Triangles und Lines benutzen das.
- **`starFragmentShader`** macht den hübschen Stern-Effekt:
  - **`point_coord`** ist eine Hardware-Koordinate, die innerhalb eines `point`-Primitivs von (0,0) bis (1,1) läuft.
  - `length(point - 0.5) > 0.5` ⇒ `discard_fragment()` macht aus dem Quadrat einen Kreis.
  - `smoothstep(0, 0.5, dist)` gibt einen weichen Falloff: hell in der Mitte, durchsichtig am Rand.
  - Das simuliert *Bloom* ohne Multi-Pass.

### 5.4 Textured Quads

```cpp
vertex TextureRasterizerData textureVertexShader(uint vertexID [[vertex_id]],
                                                  constant VertexUV *vertices [[buffer(0)]],
                                                  constant Uniforms2D &uniforms [[buffer(1)]]) { … }

fragment float4 textureFragmentShader(TextureRasterizerData in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    return tex.sample(s, in.texCoord);
}
```

- **`VertexUV`** liefert UVs statt Farbe. Der Vertex-Shader interpoliert sie in den Rasterizer.
- **`constexpr sampler`** wird zur Compile-Zeit definiert — kein Sampler-Objekt aus Swift nötig.
- **`tex.sample(s, in.texCoord)`** liest mit linearem Filtering aus. Wir nutzen Mip-Maps nicht, weil die Pixmaps so klein sind.
- **`[[texture(0)]]`** korrespondiert zu `enc.setFragmentTexture(obj.texture, index: 0)` im Swift-Code.

### 5.5 MPS (Metal Performance Shaders) — eine Klarstellung

Du hast im Inhaltsverzeichnis "MPS (Metal Shader …)" notiert. Wichtig zu unterscheiden:

- **Metal Shading Language (MSL)** und **Metal Pipelines** sind das, was wir oben besprochen haben — du als Entwickler schreibst Shader und stellst Render-Pipelines auf.
- **Metal Performance Shaders (MPS)** ist ein *separates Framework* (`import MetalPerformanceShaders`), das Apple mitliefert. Es enthält *fertige* GPU-Kernels für Image-Processing (Gauß-Blur, Convolution), für Lineare Algebra und für Machine Learning. **MPS wird in diesem Projekt nicht benutzt.**

Wenn du MPS einsetzen wolltest, wäre das etwa ein Bloom-Pass mit `MPSImageGaussianBlur`. Für ein klassisches Lunar-Lander-Spiel ist das Overkill — die Hand-geschriebenen 2D-Shader sind ohnehin GPU-trivial.

### 5.6 Wie die Shader gebaut werden

Xcode kompiliert alle `.metal`-Dateien zur Build-Zeit in eine `default.metallib`, die im App-Bundle landet. `device.makeDefaultLibrary()` lädt sie. Du kannst auch zur Laufzeit `device.makeLibrary(source: "...", options: nil)` aufrufen, aber das wäre nur für Shader-Hot-Reload oder Editor-Anwendungen relevant.

---

## 6. Code Review

Abschließend ein ehrliches Review aus Software-Engineering-Sicht. Stärken zuerst, dann Schwächen, dann konkrete Verbesserungsvorschläge.

### 6.1 Stärken

1. **Saubere Schichtung Renderer ↔ ViewController.**
   Die Callbacks (`onStateChange`, `onFuelPickup`, `onLightPickup`) und der `InputState`-Struct als gemeinsamer Boolean-Eingang sind eine in der Praxis robust funktionierende Entkopplung. Beide Plattformen teilen sich tatsächlich denselben Renderer; die Trennung ist nicht nur theoretisch.

2. **Frame-rate-Unabhängigkeit.**
   `dt` wird konsequent durch alle Update-Funktionen geleitet und am Eintrag auf `1/30` geklemmt. Die Akkumulator-basierte Spawn-Logik ist zeitexakt.

3. **Konfiguration zentral und lesbar.**
   `GameConfig.swift` ist das, was es verspricht: ein Tweak-Panel, ohne dass man im Renderer baggern muss. Die in-line-Kommentare zur Spawn-Formel und zu den `…MaxSize`-Werten sind wertvoll.

4. **Kein Magic-Numbers-Wildwuchs in der Spielmechanik.**
   `mainThrustPower`, `maxLandingVSpeed`, `mainFuelRate` etc. sitzen oben in der Datei als `private let` — leicht zu finden, leicht zu ändern.

5. **Schöne Detailpolitur.**
   `hitFactor = 0.6` bei Floating-Object-Kollisionen, `0.6 s`-Cooldown bei Retry, Wind-Lautstärke-Mapping, `dt`-Cap, `landerX`-Wrap-Around. Diese kleinen Dinge sind das, was Spiele "gut anfühlen" lassen.

6. **Ressourcenschonende Asset-Pipeline.**
   PNG-Downsampling beim Laden (statt zur Laufzeit), ein einziger großer Vertex-Buffer als Linear Allocator, ein paar geteilte Pipelines. Das ist effizient, ohne übertrieben optimiert zu sein.

7. **Gemeinsame Header-Datei für Shader und Swift.**
   `ShaderTypes.h` mit `#ifdef __METAL_VERSION__` ist die textbookmäßig richtige Lösung.

### 6.2 Schwächen / Risiken

1. **Renderer ist eine 2000-Zeilen-Klasse.**
   Das ist im CLAUDE.md als bewusste Entscheidung markiert und in der jetzigen Form noch lesbar. Aber: Spielzustände (FSM), Physik, Kollision, Asset-Loading, Rendering und Font sind alle eine Klasse, eine Datei. Spätestens, wenn UI-Themes, Tutorial-Overlay und vielleicht ein zweiter Renderer-Pfad dazukommen, kippt das. Eine Aufteilung nach *Modulen* (`PhysicsState`, `Particles`, `Terrain`, `Renderer`, `VectorFont`) wäre nicht-invasiv möglich, indem man die Daten in `struct`s mit Methoden auslagert. Ich würde damit warten, bis die Datei >3000 LOC überschreitet.

2. **Force-Unwraps in Init-Code.**
   `self.device = metalKitView.device!`, `self.commandQueue = self.device.makeCommandQueue()!`, `vertexBuffer = device.makeBuffer(...)` — alles ohne `guard`. Wenn das System unter Ressourcendruck ist, crasht die App auf Devicegrenze. Mehr Defensive (`guard let`, `return nil`) wäre konsistenter mit dem `init?`-Pattern.

3. **`drawableSize` und `gameHeight` werden mutiert, ohne dass davon abhängige Werte (Stars, Terrain) neu gerechnet werden.**
   `mtkView(_:drawableSizeWillChange:)` ruft `generateStars()` und `generateTerrain()` nur beim *ersten* Aufruf (`initialSetupDone`). Wenn das Fenster auf macOS resized wird (z. B. zwischen iPad-Landscape und Mac-Vollbild), bleibt das Sternenfeld in alten Koordinaten. Auf dem App-Store-Mac-Build ist das vielleicht kein Problem (Fenster wird selten resized), aber im Quellcode ist das eine *latente Inkonsistenz*.

4. **`charSegs(_:)` ist ein Mega-Switch ohne Daten-Tabelle.**
   Jede Glyph-Definition ist im Source eingebrannt. Schöner wäre eine `static let glyphs: [Character: [(Float, Float, Float, Float)]]`-Tabelle, die initialisiert wird. Aber: der Switch ist vermutlich nicht langsamer (Compiler macht eine Sprung-Tabelle daraus) und der Code ist im Stil eines 80er-Vektorspiels.

5. **Audio-Ressourcen-Pfad ist hartcodiert dupliziert.**
   `setupSoundEffects()` in `GameViewController.swift` und in `iOSGameViewController.swift` listet dieselben Dateinamen, dieselben Volumes, dieselben Loops. Eine kleine `AudioBank`-Klasse, die *einmal* alles lädt und beiden ViewControllern serviert, würde Drift verhindern.

6. **Wind-Sound-Datei `wind_02_gusyt` (statt `_gusty`).**
   Tippfehler im Dateinamen wird vom Code stoisch repliziert. Funktional egal, aber unschön.

7. **Skript-FSM ohne explizite Übergangstabelle.**
   Die Übergänge sind über die Datei verstreut: `update(dt:)` macht Zeit-Trigger, `checkCollision()` setzt `.crashed`/`.tippedOver`/`.landed`, `confirmName()` setzt `.highscores`. Das ist okay, aber bei FSM-Erweiterungen (etwa Pause-State) muss man jede Stelle einzeln finden. Eine zentrale `transition(_:to:)`-Methode, die `stateChangeTime` und `onStateChange?` einheitlich setzt, würde Code-Duplikation reduzieren.

8. **`lives` ist Renderer-Eigenschaft, aber nur in `checkCollision`/`checkFloatingCollisions` dekrementiert.**
   Das ist konsistent, aber `lives` und `stateChangeTime` werden teils im Renderer, teils vom ViewController (via Read-Only-Lesen) verwendet, um Retry-Cooldown zu prüfen. Die Cooldown-Logik wäre als Method auf Renderer (`canRetry: Bool`) sauberer als eine `0.6`-Konstante in beiden ViewControllern.

9. **Tests sind vorhanden, aber leer.**
   `LunarLanderTests/`, `LunarLanderiOSTests/` existieren als Targets, sind aber Boilerplate. Ein paar Tests auf die *reine* Logik (Highscore-Sortierung, Spawn-Akkumulator, Score-Formel) wären leicht zu schreiben und wertvoll als Regression-Netz, gerade weil das Spiel zwei Targets betrifft.

10. **`update(dt:)` ruft `onStateChange?` nicht überall konsistent.**
    Bei `.landed → .levelTransition` und `.crashed → .gameOver` wird der State gesetzt, aber `onStateChange?` *nicht* gefeuert. Das ist Absicht (`.gameOver` braucht keinen Sound-Trigger), aber inkonsistent dokumentiert. Ein expliziter Kommentar oder besser eine `transition(to:)`-Methode (siehe Punkt 7) würde das auflösen.

### 6.3 Konkrete Verbesserungsvorschläge

In aufsteigender Reihenfolge nach Aufwand:

1. **`transition(to newState: GameState)` als zentrale Methode.** Setzt `gameState`, `stateChangeTime`, und ruft `onStateChange?`. ~10 Zeilen, dedupliziert 8 Stellen.
2. **`Renderer.canRetry: Bool { (gameState == .crashed || .tippedOver) && lives > 0 && gameTime - stateChangeTime >= 0.6 }`** — die Cooldown-Konstante wandert in den Renderer, die ViewControllers werden schlanker.
3. **`generateStars()` und `generateTerrain()` bei jeder Aspect-Ratio-Änderung neu rechnen.** 3 Zeilen Conditional in `mtkView(_:drawableSizeWillChange:)`.
4. **Audio in eine eigene `AudioBank`-Klasse.** Sie hält `enginePlayer`, `windPlayer`, …, kennt nur Strings und Volumes; ViewControllers leiten nur Calls weiter.
5. **`Renderer` aufteilen in vier Dateien:**
   - `Renderer+Pipelines.swift` (Setup),
   - `Renderer+Drawing.swift` (alle `drawXxx`),
   - `Renderer+Logic.swift` (`update`, `checkCollision`, `setupLevel`),
   - `Renderer+Font.swift` (`drawText`, `charSegs`).
   Swift `extension`-Pattern erlaubt das ohne Verlust von Member-Zugriff.
6. **Tests für reine Logik:** Score-Formel, Highscore-Sort, Akkumulator (3-4 Klassen, ~80 LOC).
7. **Per-Level-Pixmap-Pools** (im CLAUDE.md schon als Roadmap markiert): `GameConfig.lightPool(for level: Int) -> [(String, Int)]`. Der Renderer ruft beim Spawn `pool(of:atLevel:)` statt `texturePool(for:)`.

### 6.4 Was du als nächstes lesen solltest

Wenn du Swift, Metal und Apple-Spiele-Entwicklung vertiefen willst:

- Apples eigenes *Metal by Example*-Sample (Apple Developer Sample Code, "Creating and Sampling Textures") — sehr nahe an dem, was hier passiert.
- Das *Swift Programming Language*-Buch (kostenlos bei Apple) — drei Tage Lektüre, der Rest dieses Buches wird dann ein Spaziergang.
- *Metal Shading Language Specification* (PDF, Apple Developer) — Referenz für jedes `[[attribute]]`.
- Wenn du irgendwann doch SpriteKit/SceneKit anschauen willst: Vergleiche unsere Render-Schleife mit `SKScene` — du wirst sehen, was du an Kontrolle verlierst und an Bequemlichkeit gewinnst.

---

## Anhang A — Glossar

| Begriff | Bedeutung im Apple-Kontext |
|---|---|
| ARC | Automatic Reference Counting; Compiler-eingefügte retain/release |
| Bundle | Verzeichnis-Container für ausführbare App + Ressourcen |
| Delegate | Pattern: Objekt A ruft Methoden auf Objekt B (per Protokoll-Interface) |
| Drawable | GPU-Renderziel, das von MTKView pro Frame bereitgestellt wird |
| FSM | Finite State Machine |
| MSL | Metal Shading Language |
| MPS | Metal Performance Shaders (separates High-Level-Framework) |
| MTKView | UIView/NSView-Subklasse, die Metal-Drawables verwaltet |
| Optional `T?` | Wert oder `nil`; muss vor Verwendung ausgepackt werden |
| Storyboard | Visuelles XML-Format für AppKit-UI |
| `@MainActor` | Concurrency-Annotation; Code läuft auf Main-Queue |
| `@objc` | macht Swift-Methode für Obj-C-Runtime sichtbar (Selectors) |

## Anhang B — Wichtige Constants des Spiels

| Konstante | Wert | Wirkung |
|---|---|---|
| `mainThrustPower` | 3.5 | Basis-Hauptschub (Level 1) |
| `mainFuelRate` | 8.0 | Treibstoffverbrauch Hauptdüse [units/s] |
| `maxLandingVSpeed` | 2.5 | Max. Vertikalrate für sichere Landung [m/s] |
| `maxLandingHSpeed` | 2.5 | Max. Horizontalrate für sichere Landung [m/s] |
| `Renderer.gameWidth` | 1000 | Spielwelt-Breite (Konstante) |
| `Renderer.pixelsPerMeter` | 12 | Welt → Spielfeld-Skalierung |
| `maxVertices` | 131072 | Pro-Frame-Vertex-Cap (≈ 4 MB Buffer) |
| `maxFloatingObjects` | 10 | Hard-Cap gleichzeitige Floating Objects |
| `maxLives` | 3 | Leben pro Spiel |
| `HighscoreTable.maxEntries` | 10 | Anzahl der gespeicherten Highscore-Einträge |

---

*Ende des Buches.*
