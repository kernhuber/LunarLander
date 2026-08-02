# Lunar Lander

Ein 2D-Arcade-Spiel „Lunar Lander", geschrieben in **Swift** mit einem
handgeschriebenen **Metal**-Renderer. Läuft als App auf **iOS/iPadOS** und
lokal auf **macOS**. Ziel: ein Raumschiff mit begrenztem Treibstoff sicher und
aufrecht auf einer Landeplattform aufsetzen — trotz Schwerkraft, Wind,
umherfliegender Objekte und knapper Ressourcen.

Dieses Repository dient als **Trainingsmaterial**. Du darfst den Code
herunterladen, ausführen, untersuchen und lokal beliebig verändern.

---

## Was dieses Spiel ausmacht

- **Eigener Metal-Renderer** — keine Spiel-Engine, kein SpriteKit/SceneKit.
  Terrain, Partikel, Sterne und sogar der Text (ein selbstgebauter
  **Vektor-Zeichensatz**) werden von Hand gezeichnet.
- **Monolithischer Kern** — `LunarLander/Renderer.swift` (~1600 Zeilen) enthält
  Renderpipeline, Physik, Kollisionen, Textrendering und die komplette
  Spiel-Zustandsmaschine. Das ist Absicht, kein Versehen.
- **Zentrale Konfiguration** — nahezu alle Stellschrauben (Gravitation, Wind,
  Spawn-Raten, Schild-Parameter …) liegen in `LunarLander/GameConfig.swift`.
- **9 Level** mit unterschiedlicher Physik: Mond, Mars, Venus, Titan, Io und
  anschließend zyklische Alien-Level mit steigender Schwierigkeit.
- **Extras:** Wind (ab Level 2), einsammelbare/gefährliche fliegende Objekte,
  Treibstoff-Aufsammler, eine **Schild-Waffe** mit begrenzten Ladungen,
  3 Leben mit Retry, Highscores und ein Attract-/Demo-Loop mit KI-Steuerung.

---

## Steuerung

### macOS (Tastatur)

| Taste            | Aktion                                  |
|------------------|-----------------------------------------|
| `Leertaste`      | Hauptantrieb (Schub nach oben)          |
| `←` / `→`        | Seitliche Steuerdüsen                    |
| `Linke Strg`     | Schild auslösen (zerstört Objekte)       |
| `R`              | Spiel starten                            |
| `1`–`9`          | Level direkt anwählen (Cheat)            |

### iOS / iPadOS (Touch)

Bildschirm-Buttons: **Thrust** und seitliche Steuerung sowie ein **SHIELD**-
Button links. Namenseingabe für den Highscore über die Tastatur.

---

## Voraussetzungen

- **macOS** mit **Xcode** (aktuelle Version empfohlen).
- Zum Ausführen auf dem iPhone/iPad: ein Apple-Developer-Konto zum Signieren
  (für den Simulator nicht nötig).

## Projekt öffnen, bauen und starten

1. Repository klonen:
   ```bash
   git clone https://github.com/kernhuber/LunarLander.git
   cd LunarLander
   ```
2. `LunarLander.xcodeproj` in Xcode öffnen.
3. Ein **Scheme/Target** wählen:
   - **LunarLander** → macOS-App („Lunar Lander Vibes").
   - **LunarLanderiOS** → iOS/iPadOS-App (im Simulator oder auf dem Gerät).
4. **Run** (`⌘R`).

> Signierung: Für den iOS-Build ggf. unter *Signing & Capabilities* dein
> eigenes Development-Team eintragen.

---

## Projektstruktur (Kurzüberblick)

| Pfad                                   | Inhalt                                          |
|----------------------------------------|-------------------------------------------------|
| `LunarLander/Renderer.swift`           | Herzstück: Rendering, Physik, Spiellogik        |
| `LunarLander/GameConfig.swift`         | Zentrale Konfigurationswerte                     |
| `LunarLander/HighscoreManager.swift`   | Persistenz der Highscores (JSON)                 |
| `LunarLander/Shaders.metal`, `ShaderTypes.h` | Metal-Shader und geteilte Typen           |
| `LunarLander/`                         | macOS-spezifisch: AppDelegate, ViewController, Storyboard |
| `LunarLanderiOS/`                      | iOS-spezifisch: SwiftUI-App-Entry, UIKit-VC       |
| `LunarLander/Assets/`                  | Geteilte Audio-Assets                            |
| `medien/`                              | Grafik-/Medien-Rohmaterial                        |

Die Targets **LunarLander** (macOS) und **LunarLanderiOS** teilen sich die
Kern-Swift-Dateien. Wer geteilten Code ändert, sollte **beide** Targets bauen —
es ist leicht, das eine zu reparieren und das andere zu brechen.

---

## Trainingsmaterial in diesem Repo

- **`CLAUDE.md`** — ausführliche Projektdokumentation: Architektur, Feature-
  Beschreibungen (Schild, fliegende Objekte, Demo-Loop), Konventionen. Gedacht
  als Kontext für KI-Assistenten wie *Claude Code*, aber auch für Menschen gut
  lesbar.
- **`GAME_SPEC.md`** — eine vollständige, sprachunabhängige Spielbeschreibung
  (inkl. aller Formeln und externer Assets), mit der sich das Spiel in einer
  **beliebigen** Sprache/Plattform (C++/DirectX, C#/MonoGame, Kotlin/Android,
  JS/WebGL, Python …) nachbauen lässt.
- **`CONVERT_GAME.md`** — der Aufgaben-Prompt, aus dem `GAME_SPEC.md` erzeugt
  wurde. Zeigt, wie man eine KI zum Erstellen einer solchen Spezifikation
  anleitet.

---

## Ideen zum Experimentieren

Fast alles Interessante lässt sich über `GameConfig.swift` verändern, ohne den
Renderer anzufassen:

- Gravitation, Windstärke oder Schub eines Levels verstellen.
- Spawn-Raten und Bonuswerte der fliegenden Objekte anpassen.
- Anzahl der Leben (`maxLives`) oder Schild-Ladungen (`maxShieldBlasters`) ändern.
- Eigene Bild-Assets für fliegende Objekte hinzufügen (siehe die
  `lightObjects` / `heavyObjects` / `fuelObjects`-Einträge).

Weitergehende Aufgaben findest du inspiriert durch `GAME_SPEC.md` — z. B. das
Spiel in einer anderen Sprache nachbauen.

---

## Hinweise zur Nutzung

Das Repository ist **öffentlich und lesbar**. Du kannst es klonen und lokal
verändern, aber **nicht** in dieses Original-Repo zurückschreiben. Für eigene
Änderungen, die du online sichern möchtest, forke das Projekt oder lege ein
eigenes Repository an.
