# Lunar Lander — Vollständige Spielbeschreibung zum Nachbau

Diese Datei beschreibt das Spiel **Lunar Lander** so vollständig, dass eine KI oder ein Entwickler es in einer beliebigen Programmiersprache (z. B. C++/DirectX, C#/MonoGame, Java/Kotlin auf Android, JavaScript/WebGL, Python) nachbauen kann, ohne den Swift-Code zu übersetzen. Sie nennt alle Spielregeln, alle Formeln und alle externen Dateien.

Die Beschreibung ist hierarchisch aufgebaut:

1. Sinn des Spiels
2. Bedienung (Computer / Touch)
3. Attract-Loop (Vorführmodus)
4. Spielablauf, Zustandsautomat
5. Physik und alle Formeln
6. Spielobjekte (Lander, fliegende Objekte, Schild, Terrain, Partikel)
7. Punktevergabe und Highscores
8. Zentrale Konfiguration (`GameConfig`)
9. Grafik-Architektur: Renderpipeline, Koordinatensystem, der Vektor-Zeichensatz
10. Externe Assets (Bild- und Ton-Dateien)
11. Plattformhinweise

Wo eine konkrete Zahl oder Formel im vorhandenen Swift-Code steht, wird die Quelldatei genannt (z. B. `Renderer.swift`, `GameConfig.swift`). Diese Verweise dienen als Beleg, nicht als Übersetzungsauftrag — die Beschreibung selbst enthält alle nötigen Informationen.

---

## 1. Sinn des Spiels

Der Spieler steuert ein Raumschiff („Lander“), das mit begrenztem Treibstoff aus großer Höhe auf eine markierte **Landeplattform** auf der Oberfläche eines fremden Planeten herabsinken soll. Ziel jeder Ebene (Level) ist eine **weiche, aufrechte Landung** mit den Landebeinen exakt auf der Plattform.

Drei Hauptgefahren:

- **Schwerkraft** zieht den Lander permanent nach unten; der Spieler muss mit dem Hauptantrieb gegensteuern, was Treibstoff kostet.
- **Wind und Luftwiderstand** (ab Level 2) drücken den Lander seitlich weg.
- **Fliegende Objekte** kreuzen den Luftraum. Manche sind harmlos und geben Bonuspunkte, manche zerstören den Lander, eine Sorte füllt Treibstoff nach.

Als Gegenwehr besitzt der Spieler pro Level eine begrenzte Anzahl **Schild-Blaster** (Schutzschild-Waffe), die alle gefährlichen Objekte in einem Radius um den Lander zerstören.

Gelingt die Landung, geht es ins nächste, schwerere Level. Bei einem Crash verliert der Spieler ein Leben; bei null Leben ist das Spiel vorbei. Erreicht der Gesamtpunktestand einen Platz in der Bestenliste, darf der Spieler seinen Namen eintragen.

**Eine Landung gilt als erfolgreich, wenn gleichzeitig gilt:**

- Beide Landebeine stehen vollständig innerhalb der Plattform.
- Vertikale Geschwindigkeit ≤ Grenzwert (`maxLandingVSpeed = 2.5` m/s).
- Horizontale Geschwindigkeit ≤ Grenzwert (`maxLandingHSpeed = 2.5` m/s).

Ist die Vertikalgeschwindigkeit sicher, aber die Horizontalgeschwindigkeit zu hoch, **kippt** der Lander um (eigener Fehlerzustand). Sonst **zerschellt** er.

---

## 2. Bedienelemente

Eingaben werden in einen einfachen Zustand mit drei Booleans überführt (siehe `InputState` in `Renderer.swift`):

- `thrustMain` — Hauptantrieb (nach oben schiebend)
- `thrustLeft` — Seitenschub nach links
- `thrustRight` — Seitenschub nach rechts

Zusätzlich gibt es einen kantengetriggerten **Schild-Auslöser** (kein gehaltener Zustand, sondern ein Einzelereignis) und kontextabhängige Tasten zum Starten/Weiter.

### 2.1 Computer (Tastatur, Desktop)

Verhalten aus `GameViewController.swift` (macOS, NSEvent-Monitore):

| Taste | Funktion |
|---|---|
| **Leertaste** | Hauptantrieb (gedrückt = Schub) |
| **Pfeil links** | Seitenschub links (gedrückt halten) |
| **Pfeil rechts** | Seitenschub rechts (gedrückt halten) |
| **Linke Strg-Taste** | Schild-Blaster auslösen (nur die Abwärtsflanke zählt — einmal pro Druck) |
| **R** | Neues Spiel starten (auf Logo-, Highscore- oder Demo-Bildschirm) |
| **Tasten 1–9** | Cheat: direkt in das gewählte Level springen (wenn `cheatLevelSelectEnabled` aktiv) |
| **beliebige Taste** | Nach Crash/Umkippen mit verbleibenden Leben: aktuelles Level neu starten (nach 0,6 s Sperrzeit) |
| **Buchstaben/Leerzeichen** | Bei Namenseingabe: Zeichen anhängen (max. 10) |
| **Rücktaste** | Bei Namenseingabe: letztes Zeichen löschen |
| **Eingabetaste** | Bei Namenseingabe: bestätigen |

Wichtig: Die Schild-Auslösung ist **flankengetriggert**. Solange die Taste gehalten wird, darf nur **ein** Schild ausgelöst werden; erst nach Loslassen und erneutem Drücken folgt der nächste. Im Code wird dazu ein Merker `controlKeyHeld` gehalten.

Spieltasten (Leertaste, Pfeile) sollten „verschluckt“ werden, damit das Betriebssystem keinen Fehlton ausgibt.

### 2.2 Touch-Gerät (iOS/Android-artig)

Verhalten aus `iOSGameViewController.swift`. Es gibt vier halbtransparente Tasten, die nur während `playing` sichtbar sind (Alpha animiert auf 0,35 ein bzw. auf 0 aus):

- **THRUST** — große Taste (144×144 px) unten links. Touch-Down = Schub an, Touch-Up/Cancel = aus.
- **◀ / ▶** — zwei Tasten (je 90×90 px) unten rechts (rechte Taste außen, linke daneben). Halten = Seitenschub.
- **SHIELD** — Taste (90×90 px) oberhalb der THRUST-Taste. Touch-Down löst den Schild aus (Einzelereignis).

Buttons sind farbcodiert: Thrust orange, Seitenschub blau, Schild türkis; alle abgerundet (cornerRadius 16), mit Rahmen.

Außerhalb des Spiels (Logo, Highscores, Demo) startet ein **Tippen auf den Bildschirm** ein neues Spiel. Nach Crash/Umkippen (mit Leben übrig, nach 0,6 s) startet ein Tippen das Level neu.

Die **Namenseingabe** nutzt auf Touch-Geräten ein systemeigenes Textfeld mit Tastatur (Großbuchstaben erzwungen, max. 10 Zeichen, nur Buchstaben und Leerzeichen; „Done“ bestätigt). Da die Bildschirmtastatur im Querformat ca. die unteren 55 % verdeckt, wird das Eingabefeld im **oberen** Bildschirmbereich platziert.

Auf dem iPhone läuft das Spiel **nur im Querformat**, auf dem iPad in allen Lagen.

---

## 3. Attract-Loop (Vorführmodus)

Wenn niemand spielt, läuft eine Endlosschleife aus drei Bildschirmen (Zustände `logo → highscores → demo → logo …`). Zeitsteuerung aus `update(dt:)` in `Renderer.swift`:

1. **Logo** (`logo`): Vollflächiges Logo-Bild (Datei `Logo.png`), darüber blinkender Text „PRESS R TO START“ bzw. „TAP TO START“, darunter eine Steuerungs-Kurzanleitung. Sternenhintergrund. Dauer **7 Sekunden**, dann weiter.
2. **Bestenliste** (`highscores`): Titel „HIGH SCORES“, Tabelle mit Rang, Name, Punktzahl, Level (Top 10). Ränge 1–3 in Gold/Silber/Bronze. Blinkender Start-Hinweis. Dauer **7 Sekunden**, dann weiter.
3. **Demo** (`demo`): Eine KI spielt ein echtes Level vor (Standard: **Level 2**, weil dort Wind und fliegende Objekte vorkommen und der Schild vorgeführt werden kann). Endet nach spätestens `demoMaxDuration` (im Code 50 s; CLAUDE.md nennt 30 s als ursprüngliche Absicht — der Wert ist eine zentrale Konstante) oder früher bei Landung/Crash/Umkippen. Danach zurück zum Logo. Eine pulsierende „DEMO“-Beschriftung und ein Start-Hinweis liegen über dem Spielbild.

Während des gesamten Attract-Loops läuft Hintergrundmusik (`Lunar Descent Loop.mp3`), sofern `attractMusicEnabled` aktiv ist.

### 3.1 Demo-KI (Autopilot)

Aus `updateDemoAI()`. Die KI setzt dieselben `InputState`-Flags wie ein Mensch. Algorithmus pro Frame:

- **Schild:** Wenn Schilde übrig sind und gerade keiner aktiv ist, prüfe alle lebenden schweren Objekte. Liegt eines näher als **50 Spieleinheiten** (euklidische Distanz Mittelpunkt-zu-Mittelpunkt), löse sofort einen Schild aus.
- **Horizontal (Totband + Hysterese, damit die Düsen nicht flattern):**
  - `dx = Plattformmitte − landerX`, in Meter: `dxMeters = dx / pixelsPerMeter`.
  - Zielgeschwindigkeit `hTarget = clamp(dxMeters * 0.4, −3.0, +3.0)`.
  - `hError = hTarget − velocityX`.
  - Wenn `hError > 0.5`: Schub rechts an, links aus. Wenn `hError < −0.5`: Schub links an, rechts aus. Sonst beide aus.
- **Vertikal (Zielsinkrate je Höhenband, mit Hysterese auf dem Hauptantrieb):**
  - Höhe über Grund `altitude = (landerY − landerH/2 − legHeight − Terrainhöhe(landerX)) / pixelsPerMeter`.
  - Sinkrate `vSpeed = −velocityY` (positiv = sinkt).
  - Zielsinkrate und Totband nach Höhe:
    - `altitude > 40` → Ziel 3.0, Totband 0.6
    - `altitude > 15` → Ziel 1.8, Totband 0.5
    - `altitude > 5` → Ziel 1.0, Totband 0.35
    - sonst → Ziel 0.6, Totband 0.25
  - Wenn `vSpeed > Ziel + Totband`: Hauptantrieb an. Wenn `vSpeed < Ziel − Totband`: aus. Im Totband: vorigen Zustand beibehalten (Hysterese).

Die Demo-KI gilt als Referenz für „gutes Spielgefühl“ — sie zeigt, welche Sinkraten in welcher Höhe sicher sind.

---

## 4. Spielablauf und Zustandsautomat

Das gesamte Spiel ist ein endlicher Automat. Die Zustände (siehe `enum GameState`):

```
logo, highscores, demo, playing, landed, levelTransition,
crashed, tippedOver, gameOver, enteringName
```

### 4.1 Attract-Pfad

```
logo --(7s)--> highscores --(7s)--> demo --(Ende/Timeout)--> logo --> ...
```

### 4.2 Spiel-Pfad

```
playing --(weiche Landung auf Pad)--> landed --(1.5s)--> levelTransition --(2.0s)--> (nächstes Level) playing
playing --(zu schnell/daneben)--> crashed ----+
playing --(zu viel Horizontalspeed)--> tippedOver --+
                                                    |
   (Leben > 0): Zustand hält, Spieler drückt Taste --> retry: gleiches Level neu, playing
   (Leben == 0, nach 2.5s): --> gameOver --(2.0s)--> qualifiziert? --ja--> enteringName --> highscores
                                                                  --nein--> logo
```

Detaillierte Zeit- und Übergangsregeln (aus `update(dt:)`):

- **`landed`**: 1,5 s lang Partikel weiterlaufen lassen und „LANDED SAFELY!“ samt Punktevorschau zeigen. Danach Levelpunkte berechnen, zum Gesamtpunktestand addieren, nach `levelTransition`.
- **`levelTransition`**: 2,0 s Anzeige „LEVEL n COMPLETE!“, Levelpunkte, Gesamtpunkte und eine Vorwarnung auf die nächsten Bedingungen. Danach `setupNextLevel()` (Level +1, neues Setup, `playing`).
- **`crashed` / `tippedOver`**: Partikel/Explosion laufen weiter. Nur wenn **keine Leben** mehr übrig sind, nach 2,5 s automatisch zu `gameOver`. Sind noch Leben da, **hält** der Zustand, bis der Spieler (nach 0,6 s Sperre) eine Taste drückt / tippt → `retryCurrentLevel()`.
- **`gameOver`**: 2,0 s Anzeige. Danach: Qualifiziert der Gesamtpunktestand für die Bestenliste? Ja → `enteringName`, sonst → `logo`.
- **`enteringName`**: Cursor blinkt, Spieler tippt Namen, bestätigt → Eintrag speichern → `highscores`.

### 4.3 Spielstart-Funktionen

- **Neues Spiel** (`startNewGame`): Level = 1, Punkte = 0, Leben = `maxLives` (3), Level aufbauen, `playing`.
- **Cheat-Start** (`startGameAtLevel(n)`): wie oben, aber Level = clamp(n, 1, 9).
- **Nächstes Level** (`setupNextLevel`): Level +1, Setup, `playing`. (Punkte/Leben bleiben.)
- **Retry** (`retryCurrentLevel`): nur erlaubt aus `crashed`/`tippedOver` mit Leben > 0; baut **dasselbe** Level neu auf (neues Terrain, voller Treibstoff, Schilde aufgefrischt), `playing`.

### 4.4 Level-Setup (`setupLevel`)

Pro Levelstart passiert:

1. **Physik konfigurieren** (siehe Abschnitt 5.2) — Schwerkraft, Schub, Wind, Luftwiderstand, Farben.
2. **Terrain erzeugen** (Abschnitt 6.5) inklusive Plattformposition.
3. **Startposition des Landers:** Liegt die Plattform in der rechten Bildhälfte, startet der Lander links bei `x = gameWidth · zufällig(0.1…0.3)`, sonst rechts bei `gameWidth · zufällig(0.7…0.9)`. Starthöhe `y = gameHeight − 60`. Startgeschwindigkeit 0.
4. **Schilde auffrischen:** `shieldsRemaining = maxShieldBlasters` (3). Aktive Schilde leeren.
5. **Fliegende Objekte zurücksetzen**, zwei leichte Objekte als Startbelegung einstreuen.
6. **Treibstoff berechnen** (Abschnitt 5.5).
7. Partikel und Score-Popups leeren, `InputState` zurücksetzen.

---

## 5. Physik und alle Formeln

### 5.1 Einheiten und Skalen

- **Spiel-Koordinatensystem:** Breite `gameWidth = 1000` Einheiten (fest). Höhe `gameHeight` = `gameWidth / Seitenverhältnis` des Fensters (typisch ~562–750). **Y zeigt nach oben**, y=0 ist der untere Bildrand.
- **Pixel pro Meter:** `pixelsPerMeter = 12`. Geschwindigkeiten und Beschleunigungen werden in **Metern pro Sekunde** gerechnet; Positionen in **Spieleinheiten** („Pixel“). Umrechnung über `pixelsPerMeter`.
- **Zeitschritt** `dt` in Sekunden, gemessen zwischen Frames, aber **gedeckelt auf max. 1/30 s** (`min(dt, 1/30)`), damit ein Ruckler keine Physik durch Wände tunnelt. Zielbildrate 60 fps.

### 5.2 Per-Level-Physik (`configureLevelPhysics`)

Jedes Level setzt Schwerkraft `levelGravity` (m/s²), Luftwiderstand `atmosphereDrag`, Windgrundstärke `windBase`, Windvariabilität `windVariability`:

| Level | Gravity | atmosphereDrag | windBase | windVariability | Thema/Farbe |
|---|---|---|---|---|---|
| 1 | 1.62 | 0.0 | 0.0 | 0.0 | Mond (dunkler Himmel, graues Gestein) |
| 2 | 2.0 | 0.3 | 0.3 | 0.0 | Mars (dunkelroter Himmel, Rost) |
| 3 | 2.5 | 0.5 | 0.5 | 0.3 | Venus (trübes Bernstein, Vulkangestein) |
| 4 | 3.2 | 0.7 | 0.7 | 0.5 | Titan (blaugrün, Eis) |
| 5 | 4.0 | 0.9 | 0.9 | 0.7 | Io (gelbgrün, Schwefel) |
| ≥6 | `min(4.0 + (Level−5)·0.5, 7.0)` | 1.0 | 1.2 | 0.9 | Alien-Welten, zyklisch (s. u.) |

**Schub-Skalierung** (Spielbarkeit: Schub muss > Schwerkraft sein):

```
thrustRatio   = max(1.4, 2.16 − (Level−1)·0.12)
levelMainThrust = levelGravity · thrustRatio
levelSideThrust = levelMainThrust · (sideThrustPower / mainThrustPower)
                = levelMainThrust · (2.0 / 3.5)
```

Konstanten: `mainThrustPower = 3.5`, `sideThrustPower = 2.0`, `mainFuelRate = 8.0`, `sideFuelRate = 4.0` (Treibstoff/Sekunde). In Level 1 ist das Verhältnis Schub/Schwerkraft 3.5/1.62 ≈ 2.16; höhere Level werden enger (schwerer).

**Windrichtung:** Beim Levelstart wird das Vorzeichen zufällig gewählt: `windForce = windBase · (zufällig ±1)`, `windTargetForce = windForce`, Timer 0.

**Alien-Farbzyklus ab Level 6** (`cycle = (Level − 6) mod 4`): 0 = Lila, 1 = Karmesin, 2 = Smaragd, 3 = gefrorenes Blau. Konkrete RGB-Werte siehe Abschnitt 9.6.

### 5.3 Bewegungsintegration des Landers (`updatePlaying`)

Pro Frame, in dieser Reihenfolge (semi-impliziter Euler):

```
# 1. Schwerkraft
velocityY -= levelGravity * dt

# 2. Antriebe (nur solange Treibstoff > 0)
if thrustMain  and fuel>0:  velocityY += levelMainThrust * dt;  fuel -= mainFuelRate * dt;  (Hauptdüsen-Partikel)
if thrustRight and fuel>0:  velocityX += levelSideThrust * dt;  fuel -= sideFuelRate * dt;  (Seitendüsen-Partikel)
if thrustLeft  and fuel>0:  velocityX -= levelSideThrust * dt;  fuel -= sideFuelRate * dt;  (Seitendüsen-Partikel)
fuel = max(fuel, 0)

# 3. Luftwiderstand (nur horizontal, multiplikativ)
velocityX *= (1 − atmosphereDrag * dt)

# 4. Wind (additiv auf Horizontalgeschwindigkeit)
velocityX += windForce * dt

# 5. Variabler Wind (nur wenn windVariability > 0): siehe 5.4

# 6. Position integrieren (m/s -> Spieleinheiten über pixelsPerMeter)
landerX += velocityX * pixelsPerMeter * dt
landerY += velocityY * pixelsPerMeter * dt

# 7. Horizontaler Bildschirm-Wrap (zylindrische Welt)
if landerX < 0:          landerX += gameWidth
if landerX > gameWidth:  landerX -= gameWidth

# 8. Kollisionen prüfen (Boden, fliegende Objekte), Partikel updaten
```

Die Welt ist horizontal **zyklisch**: verlässt der Lander einen Rand, erscheint er am anderen. Vertikal gibt es keinen Wrap; fällt der Lander unter `y = −50`, zählt das als Crash.

### 5.4 Variabler Wind (`windVariability > 0`)

```
windChangeTimer += dt
if windChangeTimer >= 2.0:
    windChangeTimer = 0
    windTargetForce = windBase * zufällig(−1.0 … +1.0) * (1.0 + windVariability)
# Glättung gegen Zielwert (exponentielles Nachziehen):
windForce += (windTargetForce − windForce) * dt * 0.8
```

Der Wind ändert also alle 2 s sein Ziel und nähert sich diesem weich an. Die Windstärke beeinflusst HUD-Anzeige, Windfahne und Windgeräusche.

### 5.5 Treibstoffberechnung beim Levelstart (`setupLevel`)

Der Starttreibstoff wird physikalisch so geschätzt, dass eine Landung mit Reserve möglich ist:

```
padCenter        = (landingPadStart + landingPadEnd) / 2
fallDistance     = (landerY − landingPadY − landerH/2 − legHeight) / pixelsPerMeter   # Meter
horizontalDist   = |landerX − padCenter| / pixelsPerMeter

fallTime         = sqrt(2 * max(fallDistance, 1) / levelGravity)
impactVelocity   = levelGravity * fallTime
verticalBurnTime = impactVelocity / (levelMainThrust − levelGravity)
verticalFuel     = verticalBurnTime * mainFuelRate

hTime            = sqrt(2 * max(horizontalDist, 1) / levelSideThrust)
horizontalFuel   = hTime * sideFuelRate * 2.0

windFuel         = |windBase| * fallTime * sideFuelRate * 0.5

fuelMultiplier   = max(1.2, 1.6 − (Level−1)*0.1)      # Reserve, sinkt mit Level
initialFuel      = (verticalFuel + horizontalFuel + windFuel) * fuelMultiplier
fuel             = initialFuel
```

`initialFuel` ist zugleich der Referenzwert für die Treibstoffanzeige (100 %) und für Tank-Nachfüllungen (Fuel-Objekte füllen 40 % davon).

### 5.6 Partikelphysik (`updateParticles`)

Jeder Partikel hat Position, Geschwindigkeit, Restlebensdauer und Farbe. Pro Frame:

```
life -= dt
wenn life <= 0: entfernen
x += vx * dt
y += vy * dt
vy -= levelGravity * pixelsPerMeter * 0.3 * dt      # leichte Schwerkraft auf Partikel
```

Die Partikelgeschwindigkeiten sind in **Spieleinheiten/s** angegeben (nicht m/s), daher der Faktor `pixelsPerMeter` in der Partikel-Schwerkraft. Alpha = `life / maxLife` (Ausblenden).

Partikelquellen:
- **Hauptdüse:** pro Frame `max(1, dt·150)` Partikel am unteren Lander-Ende, vx ∈ [−40,40], vy ∈ [−180,−60], Farbe gelb-orange.
- **Seitendüsen:** analog seitlich, vx in Schubrichtung 60…160, vy ∈ [−25,25].
- **Explosion:** 300 Partikel in alle Richtungen (Winkel 0…2π, Tempo 40…300, Leben 0,5…2,5 s, rot-orange) plus 80 hellere, schnellere Kern-Partikel (Tempo 60…200, Leben 0,3…1,2 s, weiß-gelb). Wird am Crash-Ort gespawnt.

---

## 6. Spielobjekte

### 6.1 Lander

Geometrie (Spieleinheiten, Mittelpunkt = `landerX, landerY`):

- Rumpfbreite `landerW = 28`, Rumpfhöhe `landerH = 34`.
- Beinspannweite `legSpread = 34`, Beinhöhe `legHeight = 10`.

Der Lander wird als Vektorgrafik aus gefüllten Dreiecken (Rumpf, Cockpit-Fenster gelb, Triebwerksdüse) und Linien (Landebeine, Seitendüsen-Stummel) gezeichnet — siehe `drawLander`. Beim Schub erscheint eine flackernde Flammen-Dreiecksgrafik unter dem Rumpf (Länge zufällig 15…30, Farbe gelb-rot, nur im Zustand `playing`).

**Umkipp-Animation:** Im Zustand `tippedOver` rotiert der Lander über 0,8 s um 90° in Kipprichtung (`tipDirection = ±1`, je nach Vorzeichen der Horizontalgeschwindigkeit beim Aufprall). Rotationswinkel `angle = tipDirection · min(elapsed/0.8, 1) · π/2`.

**Lander-Fußpunkt** (für Kollision): `footY = landerY − landerH/2 − legHeight`. Linker Fuß bei `landerX − legSpread/2`, rechter bei `landerX + legSpread/2`.

### 6.2 Bodenkollision (`checkCollision`)

```
footY     = landerY − landerH/2 − legHeight
leftFoot  = landerX − legSpread/2
rightFoot = landerX + legSpread/2
maxT      = max( Terrainhöhe(landerX), Terrainhöhe(leftFoot), Terrainhöhe(rightFoot) )

wenn footY <= maxT:   # Bodenkontakt
    onPad = (leftFoot >= landingPadStart) und (rightFoot <= landingPadEnd)
    absVY = |velocityY| ;  absVX = |velocityX|

    wenn onPad und absVY <= 2.5 und absVX <= 2.5:
        -> landed   (Lander exakt auf Pad-Höhe setzen, Geschwindigkeit 0)
    sonst wenn absVY <= 2.5 und absVX > 2.5:
        -> tippedOver  (tipDirection = sign(velocityX); Leben −1 außer im Demo)
    sonst:
        -> crashed     (Explosion spawnen; Leben −1 außer im Demo)

# Sturz aus dem Bild:
wenn landerY < −50:
    -> crashed  (Explosion; Leben −1 außer im Demo)
```

Leben werden nur außerhalb des Demo-Modus dekrementiert: `lives = max(lives − 1, 0)`.

### 6.3 Fliegende Objekte (`FloatingObject`)

Drei Klassen (`light`, `heavy`, `fuel`). Jedes Objekt hat: Typ, zugehörige Bilddatei (Textur), Bonuswert, Anzeigegröße (= Texturpixelmaße, 1:1 in Spieleinheiten), Position, Horizontalgeschwindigkeit `vx`, Rotation und Winkelgeschwindigkeit, „alive“-Flag.

**Wirkung bei Kontakt mit dem Lander:**

- **light (leicht):** Objekt verschwindet, Lander-Geschwindigkeit bleibt unverändert, `totalScore += bonus` (aktuell 10), ein Score-Popup „+N POINTS“ erscheint am Trefferpunkt (1 s), Sound `blurp.mp3`.
- **heavy (schwer):** löst den normalen Crash aus (`crashed`, Explosion, Crash-Sound), kostet ein Leben.
- **fuel:** Tank um `initialFuel · 0.4` auffüllen (gedeckelt auf `initialFuel`), Objekt verschwindet, Erfolgssound. Maximal **1** Fuel-Objekt gleichzeitig auf dem Bildschirm.

**Spawn-Parameter** (zentral in `GameConfig`, pro Klasse als `FloatingObjectClassConfig`):

```
effektive Spawnrate (pro Sekunde) = spawnsPerSecond · spawnLevelMultiplier · Level
effektiver Tempobereich (m/s)     = [ minInitialSpeed · speedLevelMultiplier · Level ,
                                       maxInitialSpeed · speedLevelMultiplier · Level ]
```

Konkrete Werte (aus `GameConfig.swift`):

| Klasse | spawnsPerSecond | spawnLevelMult | minSpeed | maxSpeed | speedLevelMult |
|---|---|---|---|---|---|
| light | 1.8 | 0.5 | 3.0 | 10.0 | 0.6 |
| heavy | 0.6 | 0.9 | 2.0 | 8.0 | 0.5 |
| fuel | 0.40 | 0.60 | 1.5 | 4.0 | 0.5 |

**Spawn-Mechanik (`tickRandomSpawning`, Akkumulator-Muster):** Pro Klasse wird ein Akkumulator pro Frame um `rate · dt` erhöht. Überschreitet er 1.0, wird ein Objekt erzeugt und 1.0 abgezogen (für light/heavy in einer Schleife, falls mehrere fällig). Für **fuel** gilt eine Sonderregel: Ist bereits ein Fuel-Objekt auf dem Schirm, wird der Akkumulator bei 1.0 **gehalten** (nicht weiter erhöht, kein Verlust), sodass sofort ein neues erscheint, wenn das alte den Schirm verlässt.

Maximal `maxFloatingObjects = 10` Objekte gleichzeitig.

**Spawn-Ort und -Bewegung (`spawnObject`):**

- Vertikalposition `y = zufällig(gameHeight·0.30 … gameHeight·0.80)`.
- Tempo `speedMagnitude = zufällig(speedMin … speedMax)` mit `scale = max(speedLevelMultiplier·Level, 0.01)`.
- Eintritt vom Rand (`atEdge`): zufällig von links oder rechts, knapp außerhalb (`margin = max(width·0.5+10, 25)`), `vx` nach innen gerichtet. (Beim Levelstart werden 2 leichte Objekte stattdessen auf zufälligen Bildschirmpositionen platziert.)
- Rotation: Startwinkel zufällig 0…2π, Winkelgeschwindigkeit zufällig −3…+3 rad/s.
- Textur: zufällig aus dem Pool der jeweiligen Klasse.

**Bewegung pro Frame (`updateFloatingObjects`):**

```
response = 0.18
vx += (windForce − vx) * response * dt      # sanfter Wind-Einfluss (schwächer als auf Lander)
x  += vx * pixelsPerMeter * dt
rotation += angularVelocity * dt
wenn x < −60 oder x > gameWidth+60: Objekt entfernen
```

**Kollision Objekt↔Lander (`checkFloatingCollisions`, AABB):** Lander-Hitbox: Halbbreite `landerW·0.5`, Halbhöhe `landerH·0.5 + legHeight·0.5`, Mittelpunkt `(landerX, landerY − legHeight·0.5)`. Objekt-Hitbox: nur **60 %** der gezeichneten Größe (`hitFactor = 0.6`), damit transparente Bildecken nicht fälschlich treffen. Überlappung per Achsenabstand: trifft, wenn `|ox−lcx| <= hw+lw` **und** `|oy−lcy| <= hh+lh`.

### 6.4 Schild-Blaster (`ActiveShield`, `deployShieldBlaster`, `updateShields`)

Eine begrenzte Verteidigungswaffe: zerstört alle **schweren** Objekte in einem Radius um den Lander.

- **Vorrat:** `maxShieldBlasters = 3`, frisch zu Beginn **jedes Levels** (Per-Level-Ressource, nicht pro Spiel).
- **Auslösen:** nur erlaubt, wenn `gameState == playing` und Vorrat > 0. Ein neuer `ActiveShield` wird an der aktuellen Landerposition erzeugt; Vorrat −1; Sound `Shield.mp3`. Mehrere Schilde können gleichzeitig laufen.
- **Parameter:** `shieldBlasterRadius = 200` Spieleinheiten, `shieldBlasterDuration = 0.7` s.
- **Radius über Zeit:** wächst in der **ersten Hälfte** linear von 0 auf den Maximalradius, **hält** in der zweiten Hälfte:
  ```
  half = duration * 0.5
  radius = (elapsed < half) ? maxRadius * (elapsed/half) : maxRadius
  ```
- **Wirkung pro Frame (`updateShields`, läuft unabhängig vom Spielzustand):** Für jeden aktiven Schild alle lebenden **schweren** Objekte prüfen; liegt eines innerhalb `radius` (Distanzquadrat-Vergleich), wird es zerstört, eine Explosion an **seiner** Position gespawnt, und `onHeavyDestroyed` ausgelöst (Crash-Sound). Schilde mit `elapsed >= duration` werden entfernt.
- **Darstellung:** 10 konzentrische zyanfarbene Ringe um den Lander; das Alpha-Profil hat seinen Höhepunkt am tatsächlichen Radius und läuft nach innen/außen aus (dickes Energieband). Während der Wachstumsphase Alpha = 1, danach lineares Ausblenden. Details siehe `drawShieldBlasters`.

### 6.5 Terrain (`generateTerrain`)

Das Gelände ist eine Polylinie aus `numSegments = 80` Segmenten über die volle Breite (`segWidth = gameWidth/80`). Höhenprofil:

```
baseH  = gameHeight * 0.18
maxVar = gameHeight * 0.22

# Landeplattform: zufällig 5 Segmente breit
padSegStart = zufällig(10 … numSegments−15)
padSegEnd   = padSegStart + 5

für jedes Segment i:
   wenn i im Pad-Bereich: Höhe vorerst 0 (wird später flach gesetzt)
   sonst:
      n  = i / numSegments
      v1 = sin(n·π·2.3) · maxVar · 0.35
      v2 = sin(n·π·5.7) · maxVar · 0.25
      v3 = sin(n·π·11.3) · maxVar · 0.15
      rnd = zufällig(−maxVar·0.12 … +maxVar·0.12)
      Höhe = baseH + v1 + v2 + v3 + rnd

# Plattform flach und plausibel:
padH = max( min(NachbarhöheLinks, NachbarhöheRechts) · 0.9 , gameHeight · 0.05 )
alle Pad-Segmente auf padH setzen

# weiche Anrampung über 3 Segmente links und rechts der Plattform:
für d = 1..3:  t = d/4;  Nachbar = Nachbar·(1−t) + padH·t

# globaler Mindestboden:
alle Höhen = max(Höhe, gameHeight · 0.05)

landingPadStart = padSegStart · segWidth
landingPadEnd   = padSegEnd   · segWidth
landingPadY     = padH
```

**Terrainhöhe an beliebigem x (`terrainHeightAt`):** lineare Interpolation zwischen den beiden umgebenden Stützpunkten; x wird vorher in `[0, gameWidth]` gewrappt (zylindrische Welt).

Gezeichnet wird das Terrain als gefüllte Dreiecke mit Farbverlauf (Oberflächenfarbe oben, dunkle Tiefenfarbe bei y=0) und einer helleren Konturlinie entlang der Oberkante.

### 6.6 Landeplattform (`drawLandingPad`)

Ein flaches Rechteck der Höhe 4 Einheiten, grün (oben hell `~(0.15,0.75,0.15)`, unten dunkler), darüber 6 kurze gelbe Markierungsstriche. Am rechten Plattformrand steht (ab Wind-Leveln) die **Windfahne**.

### 6.7 Windfahne (`drawWindFlag`)

Nur sichtbar, wenn `windBase > 0`. Eine senkrechte Stange am rechten Pad-Rand (`poleX = landingPadEnd − 5`, Höhe 28). Daran ein Dreiecks-Wimpel, der die Windrichtung zeigt:

```
strength = min(|windForce| / 0.8, 1.0)       # bei strength <= 0.05: kein Wimpel
dir      = sign(windForce)                    # +1 rechts, −1 links
tipExtend = flagLength · (0.3 + 0.7·strength) # flagLength = 16
droop     = (1 − strength) · 14               # Durchhängen bei schwachem Wind
tipX = poleX + dir·tipExtend
tipY = poleTop − flagHeight·0.5 − droop       # flagHeight = 8
```

Bei starkem Wind steht die Fahne waagerecht voll ausgestreckt, bei schwachem hängt die Spitze durch, bei Flaute verschwindet sie.

---

## 7. Punkte und Highscores

### 7.1 Levelpunkte (`calculateLevelScore`)

Nach erfolgreicher Landung:

```
fuelPercent = fuel / max(initialFuel, 1)
fuelBonus   = fuelPercent · 500

vFactor = 1 − min(|velocityY|, 2.5) / 2.5
vBonus  = vFactor · 300

hFactor = 1 − min(|velocityX|, 2.5) / 2.5
hBonus  = hFactor · 200

base       = 100
multiplier = 1 + (Level−1)·0.2
Levelpunkte = floor( (base + fuelBonus + vBonus + hBonus) · multiplier )
```

Also: viel Resttreibstoff und sanftes Aufsetzen geben mehr Punkte, und höhere Level multiplizieren stärker. Zusätzlich erhöhen leichte fliegende Objekte den `totalScore` sofort um ihren Bonus (10).

### 7.2 Bestenliste (`HighscoreManager`, `HighscoreTable`)

- Maximal **10** Einträge, sortiert nach Punkten absteigend. Jeder Eintrag: Name, Punktzahl, erreichtes Level.
- **Qualifikation:** Ein Punktestand qualifiziert sich, wenn weniger als 10 Einträge existieren **oder** er größer als der kleinste vorhandene Wert ist.
- **Persistenz:** als JSON-Datei. Pfad plattformabhängig: iOS unter `<Documents>/LunarLander/highscores.json`, Desktop unter `~/.lunarlander/highscores.json`. Beim ersten Start existiert eine **Standard-Tabelle** (NEIL 5000/L5, BUZZ 4200/L4, MICHAEL 3500/L4, PETE 2800/L3, ALAN 2200/L3, JOHN 1800/L2, JIM 1400/L2, GENE 1000/L1, SALLY 700/L1, MAE 400/L1).
- Namen: max. 10 Zeichen, Großbuchstaben, nur Buchstaben/Leerzeichen; leer → „PLAYER“.

---

## 8. Zentrale Konfiguration (`GameConfig`)

Eine bewusste Architekturentscheidung: **alle einstellbaren Spielparameter** liegen an einer einzigen Stelle (Datei `GameConfig.swift`), getrennt von der Spiellogik. Ein Nachbau sollte ein analoges zentrales Konfigurationsmodul/Singleton anlegen. Inhalt:

- **Debug/Cheat:** `cheatLevelSelectEnabled` (Zifferntasten springen ins Level).
- **Audio-Schalter:** `attractMusicEnabled`, `gameplayMusicEnabled` (Standard aus), `soundEffectsEnabled`.
- **Fliegende-Objekt-Klassen:** je ein `FloatingObjectClassConfig` für light/heavy/fuel mit den Feldern `spawnsPerSecond`, `spawnLevelMultiplier`, `minInitialSpeed`, `maxInitialSpeed`, `speedLevelMultiplier` (Werte siehe 6.3).
- **Bilderlisten je Klasse:** Listen von `(Dateiname, Bonus)`. Diese verweisen direkt auf die mitgelieferten PNGs (siehe Abschnitt 10). Neue Grafik = nur ein neuer Listeneintrag, keine Logikänderung.
- **Skalierungsgrenzen** `lightObjectMaxSize`, `heavyObjectMaxSize`, `fuelObjectMaxSize` (in Pixeln; aktuell 150/4, 200/4, 170/4 = 37/50/42). Beim Laden wird jedes PNG so heruntergerechnet, dass seine längere Kante ≤ diesem Wert ist. Da die **Anzeigegröße im Spiel direkt aus den geladenen Texturpixeln** stammt, steuert dieser Wert zugleich die Sprite-Größe im Spielfeld.
- **Schild:** `maxShieldBlasters = 3`, `shieldBlasterRadius = 200`, `shieldBlasterDuration = 0.7`.
- **Demo:** `demoLevel = 2`, `demoMaxDuration`.

Konstanten, die in der Spiellogik selbst stehen (in `Renderer.swift`, oberer Bereich), und die ein Nachbau ebenfalls zentral halten kann: `mainThrustPower`, `sideThrustPower`, `mainFuelRate`, `sideFuelRate`, `maxLandingVSpeed`, `maxLandingHSpeed`, `gameWidth`, `pixelsPerMeter`, Lander-Maße, `maxLives`, `maxFloatingObjects`.

---

## 9. Grafik-Architektur

Das Spiel benutzt **keine** Spiel-Engine, kein SpriteKit/SceneKit und **keine** System-Textroutinen. Alles wird von Hand mit einfachen 2D-Primitiven (Punkte, Linien, gefüllte Dreiecke, texturierte Quads) gezeichnet. Das macht den Nachbau in jeder Grafik-API (DirectX, OpenGL/WebGL, Vulkan, Canvas2D) unkompliziert.

### 9.1 Renderpipeline (abstrakt)

Es genügen **vier** Zeichenoperationen, die jeweils einen Stapel Vertices hochladen und in einem Draw-Call ausgeben (Original: `upload(...)` in `Renderer.swift`):

1. **Punkte** — für die Sterne, mit einem speziellen Punkt-Shader (runder, weicher Punkt).
2. **Linien** (Liste unabhängiger Liniensegmente) — für Vektor-Text, Lander-Konturen, Schildringe, Gitter, Fuel-Balkenumriss.
3. **Dreiecke** (Liste, je 3 Vertices ein gefülltes Dreieck) — für Terrain, Lander-Rumpf, Plattform, Partikel, HUD-Hintergrund, Flammen, Windfahne.
4. **Texturierte Quads** — für Logo und fliegende Objekte (zwei Dreiecke mit UV-Koordinaten und Texturabtastung).

Ein Vertex trägt: Position (2D) und entweder Farbe (RGBA) **oder** Texturkoordinate (UV). Siehe `Vertex2D` und `VertexUV` in `ShaderTypes.h`.

**Blending:** durchgehend Standard-Alpha-Blending: `out = srcAlpha·src + (1−srcAlpha)·dst`. In DirectX/OpenGL entspricht das `SrcAlpha / OneMinusSrcAlpha`.

**Bildschirm löschen:** Zu Beginn jedes Frames wird mit der Himmelsfarbe `skyColor` des Levels gefüllt.

**Zeichenreihenfolge** (Painter's Algorithm, kein Tiefenpuffer). Beispiel `playing`: Sterne → Terrain → Plattform (inkl. Windfahne, fliegende Objekte, Schildringe, Score-Popups) → Partikel → Lander → HUD. Andere Zustände kombinieren dieselben Bausteine plus Overlays (siehe `draw(in:)`).

### 9.2 Koordinatensystem und Vertex-Transformation

Intern wird in **Spieleinheiten** gerechnet (Breite 1000, y nach oben). Vor der Ausgabe werden sie auf die Pixelgröße der Zeichenfläche skaliert:

```
gx(x) = x / gameWidth  · drawableWidthInPixels
gy(y) = y / gameHeight · drawableHeightInPixels
```

Im Vertex-Shader werden Pixelkoordinaten in Clip-Space (−1…+1) überführt (Original `vertexShader2D` in `Shaders.metal`):

```
clip = (pixelPos / (viewportSize / 2)) − 1
position = (clip.x, clip.y, 0, 1)
```

Da y nach oben zeigt und der Clip-Space ebenfalls y-nach-oben ist, ist keine Y-Spiegelung nötig. **In APIs mit y-nach-unten (z. B. DirectX, Canvas2D) muss die Y-Achse hier gespiegelt werden** (`clip.y = 1 − …`), oder das Koordinatensystem entsprechend angepasst werden.

### 9.3 Die vier Shader (abstrakt)

Aus `Shaders.metal` — jeweils trivial in HLSL/GLSL nachzubauen:

- **Farbiger Vertex-Shader:** transformiert wie oben, reicht die Vertexfarbe durch.
- **Einfacher Fragment-Shader:** gibt die interpolierte Farbe aus.
- **Stern-Fragment-Shader:** zeichnet pro Punkt einen weichen Kreis. Mit den Punkt-Koordinaten innerhalb des Punkts (`pointCoord` ∈ [0,1]²): `dist = |coord − 0.5|`; ist `dist > 0.5`, Fragment verwerfen; sonst `alpha = (1 − smoothstep(0, 0.5, dist)) · vertexAlpha`. Ergibt runde, an den Rändern weiche Sterne. (Wo „point sprites“ fehlen, ersetzt man jeden Stern durch ein kleines Quad mit demselben radialen Alpha.)
- **Textur-Shader:** transformiert Position, reicht UV durch, sampelt die Textur linear (`mag/min linear`). Für Logo und fliegende Objekte.

### 9.4 Sterne (`generateStars`, `drawStars`)

200 Sterne, einmal zufällig erzeugt: Position (über der unteren Geländezone, `y` in `[gameHeight·0.35, gameHeight]`), Grundhelligkeit 0,3…1,0, Funkel-Tempo 0,5…3,0, Funkel-Phase 0…2π. Pro Frame funkelt jeder Stern: `twinkle = (sin(gameTime·speed + phase)+1)/2`, Alpha = `brightness · (0.4 + 0.6·twinkle)`. Sterne werden als weiche Punkte (s. o.) in fast-Weiß gezeichnet.

### 9.5 Der Vektor-Zeichensatz (`drawText`, `charSegs`)

Sämtlicher Text (HUD, Menüs, Punkte, Namen) wird aus **Liniensegmenten** gezeichnet — es gibt keine Schriftdatei. Das ist ein zentrales Stilelement und muss originalgetreu übernommen werden.

**Layout:**
- Jedes Zeichen lebt in einer Zelle. Glyphenmaße: Breite `w = 5`, Höhe `h = 9`, Mittelhöhe `m = h/2 = 4.5` (lokale Einheiten, y nach oben, Ursprung links unten).
- Vorschub pro Zeichen: `cw = 7 · scale` (also 7 Einheiten breit inkl. Lücke, mit Skalierungsfaktor `scale`).
- Text wird vor dem Zeichnen in Großbuchstaben gewandelt.
- Eine Zeichenkette der Länge `n` belegt also `n · 7 · scale` Einheiten Breite — diese Formel wird überall zum Zentrieren benutzt (`x = mitte − textWidth/2`).
- Farbe wird pro Aufruf gesetzt; es gibt **keinen** Alphakanal im Text. „Ausblenden“ (z. B. Score-Popups) geschieht durch **Abdunkeln** der Farbe gegen Schwarz (Faktor = Restlebensanteil).

**Glyphen-Definition:** Jedes Zeichen ist eine Liste von Segmenten `(x0, y0, x1, y1)` in lokalen Einheiten. Beim Zeichnen wird jedes Segment mit `scale` skaliert und an die Cursorposition `(cx, y)` verschoben. Die vollständige Tabelle (Buchstaben A–Z, Ziffern 0–9 und Sonderzeichen `. : - / % > < + ! Leerzeichen`) steht in `charSegs(_:)` in `Renderer.swift` und ist **integraler Bestandteil dieser Spezifikation** — sie muss exakt übernommen werden, damit das Schriftbild stimmt. Zur Orientierung einige Beispiele (Original-Zitat aus `Renderer.swift`, Format `(x0,y0,x1,y1)` mit `w=5, h=9, m=4.5`):

```
A: (0,0,w/2,h),(w/2,h,w,0),(w*0.2,m*0.8,w*0.8,m*0.8)
E: (w,0,0,0),(0,0,0,h),(0,h,w,h),(0,m,w*0.7,m)
H: (0,0,0,h),(w,0,w,h),(0,m,w,m)
L: (0,h,0,0),(0,0,w,0)
O: (1,0,w-1,0),(w-1,0,w,1),(w,1,w,h-1),(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,1),(0,1,1,0)
T: (0,h,w,h),(w/2,0,w/2,h)
0: (1,0,w-1,0),(w-1,0,w,1),(w,1,w,h-1),(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,1),(0,1,1,0),(0,0,w,h)
1: (w/2-1,h,w/2,h),(w/2,0,w/2,h),(w*0.2,0,w*0.8,0)
:  (Doppelpunkt): (w/2-0.5,h*0.3,w/2+0.5,h*0.3),(w/2-0.5,h*0.7,w/2+0.5,h*0.7)
-  (Minus): (1,m,w-1,m)
%  (Prozent): (0,0,w,h),(0.5,h,0.5,h-2),(1.5,h,1.5,h-2),(0.5,h,1.5,h),(0.5,h-2,1.5,h-2),(w-1.5,2,w-1.5,0),(w-0.5,2,w-0.5,0),(w-1.5,2,w-0.5,2),(w-1.5,0,w-0.5,0)
>  (groesser): (0,h,w,m),(w,m,0,0)
+  (Plus): (w/2,1,w/2,h-1),(1,m,w-1,m)
Leerzeichen: keine Segmente
Unbekanntes Zeichen: Rahmenrechteck (0,0,w,0),(w,0,w,h),(w,h,0,h),(0,h,0,0)
```

Die übrigen Glyphen (B, C, D, F, G, I, J, K, M, N, P, Q, R, S, U, V, W, X, Y, Z, Ziffern 2–9, `.`, `/`, `<`, `!`) folgen demselben Schema und sind dem Tabelleneintrag `charSegs` in `Renderer.swift` zu entnehmen. Ein Nachbau kann diese Liste 1:1 als Daten übernehmen, ohne Swift-Code zu portieren.

### 9.6 Farben pro Level

Himmel (Clear-Farbe), Terrain-Oberfläche, Terrain-Tiefe, Terrain-Kontur. RGB jeweils 0…1 (aus `configureLevelPhysics`):

| Level/Thema | Himmel | Oberfläche | Tiefe | Kontur |
|---|---|---|---|---|
| 1 Mond | (0.01,0.01,0.06) | (0.45,0.42,0.38) | (0.12,0.11,0.10) | (0.65,0.6,0.55) |
| 2 Mars | (0.06,0.01,0.01) | (0.55,0.25,0.12) | (0.18,0.06,0.03) | (0.7,0.35,0.18) |
| 3 Venus | (0.08,0.05,0.01) | (0.35,0.30,0.15) | (0.10,0.08,0.04) | (0.55,0.45,0.20) |
| 4 Titan | (0.01,0.04,0.08) | (0.25,0.35,0.42) | (0.06,0.10,0.14) | (0.35,0.50,0.60) |
| 5 Io | (0.06,0.06,0.01) | (0.50,0.45,0.10) | (0.15,0.12,0.02) | (0.70,0.60,0.15) |
| ≥6 Lila | (0.04,0.01,0.08) | (0.40,0.20,0.50) | (0.12,0.05,0.15) | (0.55,0.30,0.65) |
| ≥6 Karmesin | (0.08,0.02,0.02) | (0.50,0.15,0.15) | (0.15,0.04,0.04) | (0.65,0.20,0.20) |
| ≥6 Smaragd | (0.01,0.06,0.03) | (0.15,0.45,0.25) | (0.04,0.14,0.07) | (0.20,0.60,0.35) |
| ≥6 Blau | (0.02,0.03,0.10) | (0.30,0.38,0.55) | (0.08,0.10,0.18) | (0.40,0.50,0.70) |

### 9.7 HUD (`drawHUD`)

Unten ein halbtransparenter schwarzer Balken (Höhe 75 Einheiten, Alpha 0,65) mit:

- **Treibstoffbalken** links: Umriss (Linien) + Füllung (Dreieck), Breite 150, Füllanteil `fuel/initialFuel`. Farbe grün, unter 25 % rot. Daneben Prozentanzeige. Label „FUEL“.
- **V.SPD** (Vertikalgeschwindigkeit `−velocityY`) und **H.SPD** (`velocityX`), grün wenn im sicheren Bereich (≤2,5), sonst rot.
- **ALT** (Höhe über Grund in Metern), **PAD-Richtung + Distanz** („< PAD“ / „PAD >“).
- **SCORE**, **LEVEL**.
- **LIVES** (grün/gelb/rot je nach 3/2/1) und **SHIELD** (zyan, gedimmt bei 0).
- **WIND**-Indikator (nur ab Level mit `atmosphereDrag > 0`): Pfeile `<`/`>`, Anzahl `min(|windForce|/0.25 + 1, 4)`, bei Flaute „---“. Stärke färbt von blau (schwach) nach rot (>0,8).

### 9.8 Score-Popups (`ScorePopup`, `drawScorePopups`)

Bei jedem Treffer eines leichten Objekts entsteht ein „+N POINTS“-Text am Trefferpunkt. Lebensdauer 1 s, driftet pro Frame um `30·dt` Einheiten nach oben, blendet durch Abdunkeln aus. Mehrere gleichzeitig möglich. Werden zu Beginn jedes Levels geleert und laufen auch in `crashed`/`tippedOver` weiter (Tick am Anfang von `update`).

---

## 10. Externe Assets (mitgelieferte Dateien)

Die Dateien liegen im Ordner `LunarLander/Assets/` und **sollen vom Nachbau wiederverwendet werden** (Bilder als Texturen, Töne als Audioclips). Dateinamen sind exakt einzuhalten, weil die Konfiguration sie referenziert.

### 10.1 Bilder (PNG)

- **`Logo.png`** — Startbildschirm-Logo, formatfüllend skaliert (Seitenverhältnis erhalten).
- **`lunar_lander_icon_1024.png`** — App-Icon (1024×1024).
- **Leichte Objekte** (Bonus +10, harmlos), referenziert in `GameConfig.lightObjects`:
  `Leichte_Objekte_Aus_Auswahl.png`, `..._Buch.png`, `..._Huhn.png`, `..._Hut.png`, `..._Jacke.png`, `..._Kleeblatt.png`, `..._Klopömpel.png`, `..._Luftpumpe.png`, `..._Regenschirm.png`, `..._Schuh.png` (Alltagsgegenstände).
- **Schwere Objekte** (gefährlich, zerstören den Lander), referenziert in `GameConfig.heavyObjects`:
  `Schwere_Objekte_auto.png`, `..._bombe.png`, `..._dampflok.png`, `..._mahlstrom.png`, `..._meteor_01.png` … `..._meteor_05.png`.
- **Treibstoff**: `Fuel.png` (referenziert in `GameConfig.fuelObjects`).

Alle Objekt-PNGs sollten Transparenz (Alpha) haben; deshalb die 60-%-Hitbox (Abschnitt 6.3). Beim Laden auf die in `GameConfig` definierte Maximalkante herunterskalieren (hochwertige Interpolation), Premultiplied-Alpha empfohlen.

> Hinweis (geplante Erweiterung, siehe CLAUDE.md): künftig sollen pro Level unterschiedliche Teilmengen dieser Bilder gewählt werden (z. B. Alltagskram auf erdähnlichen Welten, Meteoriten/Alien-Schrott auf äußeren Welten). Aktuell ziehen alle Level aus demselben globalen Pool.

### 10.2 Töne

- **`Lunar Descent Loop.mp3`** — Hintergrundmusik im Attract-Loop (Endlosschleife, Lautstärke ~0,6). Standardmäßig **nicht** während des Spiels (`gameplayMusicEnabled = false`).
- **`navigation_rocket_engine.wav`** — Triebwerksgeräusch, Endlosschleife, läuft solange irgendein Schub aktiv ist **und** Treibstoff > 0 **und** Zustand `playing`/`demo` (Lautstärke ~0,4).
- **`crash.mp3`** — Aufprall/Explosion (auch wenn der Schild ein schweres Objekt zerstört).
- **`succes.mp3`** — Erfolg: weiche Landung **und** Treibstoff-Aufnahme.
- **`blurp.mp3`** — Aufsammeln eines leichten Objekts.
- **`Shield.mp3`** — Schild-Auslösung.
- **`wind_01_low.mp3`, `wind_02_gusyt.mp3`, `wind_03_high.mp3`** — Windgeräusch nach Stärke: `|windForce| > 0.7` → high, `> 0.35` → gusty, sonst low. Endlosschleife, Lautstärke `clamp(|windForce|·0.7, 0.15, 0.7)`, weicher Wechsel bei Stärkeänderung. Nur in `playing`/`demo` und bei `atmosphereDrag > 0`. Die Audio-Logik (Datei-Auswahl, Lautstärke, alle 0,25 s aktualisiert) steht in den View-Controllern (`GameViewController.swift`, `iOSGameViewController.swift`).

Audio-Lautstärken und -Schalter sind ein guter Kandidat, ebenfalls zentral abgelegt zu werden.

---

## 11. Plattform- und Architekturhinweise

- **Trennung Logik/Eingabe:** Die gesamte Spiellogik, Physik und das Rendern liegen in einem zentralen Modul (`Renderer.swift`), bewusst monolithisch. Plattformspezifisch sind nur Eingabe und Audio (die View-Controller). Ein Nachbau sollte ähnlich trennen: ein plattformneutraler Spielkern, der pro Frame `update(dt)` und `draw()` ausführt und einen `InputState` plus Einzelereignisse (Schild, Start, Retry, Name) entgegennimmt, und eine dünne plattformspezifische Schicht für Tastatur/Touch/Audio.
- **Frame-Loop:** Pro Frame wird zuerst `dt` aus der Echtzeit bestimmt (gedeckelt auf 1/30 s), dann `update(dt)`, dann gezeichnet. Zielbildrate 60 fps.
- **Callbacks für Sound:** Der Kern meldet Zustandswechsel und Ereignisse über Callbacks (`onStateChange`, `onFuelPickup`, `onLightPickup`, `onHeavyDestroyed`, `onShieldDeployed`), damit die Audio-Schicht reagieren kann, ohne dass der Kern Audio kennt.
- **Zufall:** An vielen Stellen wird gleichverteilter Zufall genutzt (Terrain, Spawns, Partikel, Windziel). Ein Nachbau braucht einen guten Pseudozufallsgenerator; für deterministische Tests kann er geseedet werden.
- **Keine Fremdabhängigkeiten:** Das Original verzichtet bewusst auf Spiel-Engines und Drittbibliotheken; das ist gut auf andere Stacks übertragbar, weil nur einfache 2D-Primitive nötig sind.

---

## Anhang: Quelldateien als Referenz

Diese Dateien im Projekt belegen die obigen Angaben und können bei Detailfragen konsultiert werden (Zugriff vorausgesetzt):

- `LunarLander/Renderer.swift` — Spiellogik, Physik, Rendern, Vektor-Zeichensatz (`charSegs`), Zustandsautomat.
- `LunarLander/GameConfig.swift` — zentrale Konfiguration (Spawnraten, Bilderlisten, Schild- und Demo-Parameter).
- `LunarLander/HighscoreManager.swift` — Bestenliste und JSON-Persistenz.
- `LunarLander/Shaders.metal`, `LunarLander/ShaderTypes.h` — die vier Shader und die Vertex-Strukturen.
- `LunarLander/GameViewController.swift` — Tastatur und Audio (macOS).
- `LunarLanderiOS/iOSGameViewController.swift` — Touch-Steuerung und Audio (iOS).
- `LunarLander/Assets/` — alle Bild- und Tondateien.
- `CLAUDE.md` — Projektüberblick, Konventionen, geplante Erweiterungen.
