//
//  GameConfig.swift
//  LunarLander
//
//  Central configuration for game flags and settings
//

import Foundation

struct GameConfig {

    // MARK: - Debug / Cheat

    /// Allow number keys 1-9 on the attract screen to jump directly to a level
    static let cheatLevelSelectEnabled: Bool = true

    // MARK: - Audio

    /// Play background music during the attract loop (logo, highscores, demo)
    static let attractMusicEnabled: Bool = true

    /// Play background music during actual gameplay
    static let gameplayMusicEnabled: Bool = false

    /// Enable sound effects during gameplay (rocket engine, wind)
    static let soundEffectsEnabled: Bool = true

    // MARK: - Floating Objects

    /// Spawn and motion parameters for one floating-object class.
    ///
    /// Actual values at runtime are derived from the current level:
    /// - effective spawn rate (per second) = `spawnsPerSecond * spawnLevelMultiplier * level`
    /// - effective speed range (m/s) =
    ///     [`minInitialSpeed * speedLevelMultiplier * level`,
    ///      `maxInitialSpeed * speedLevelMultiplier * level`]
    ///
    /// Each spawned object draws a random magnitude inside that range and a
    /// random sign (left or right).
    struct FloatingObjectClassConfig {
        let spawnsPerSecond: Float
        let spawnLevelMultiplier: Float
        let minInitialSpeed: Float
        let maxInitialSpeed: Float
        let speedLevelMultiplier: Float
    }

    /// Light objects: frequent, fast, score +10 on contact.
    static let lightObject = FloatingObjectClassConfig(
        spawnsPerSecond:        1.8,
        spawnLevelMultiplier:   0.5,
        minInitialSpeed:        3.0,
        maxInitialSpeed:       10.0,
        speedLevelMultiplier:   0.6
    )

    /// Heavy objects: medium frequency, strong level scaling, destroy the lander on contact.
    static let heavyObject = FloatingObjectClassConfig(
        spawnsPerSecond:        0.6,
        spawnLevelMultiplier:   0.9,
        minInitialSpeed:        2.0,
        maxInitialSpeed:        8.0,
        speedLevelMultiplier:   0.5
    )

    /// Fuel containers: max 1 on screen, gentle motion. Rate here is the desired
    /// appearance rate — the in-engine cap throttles actual spawns to one at a time,
    /// and a held-accumulator pattern makes the next one appear soon after the
    /// previous leaves the screen.
    static let fuelObject = FloatingObjectClassConfig(
        spawnsPerSecond:        0.40,
        spawnLevelMultiplier:   0.60,
        minInitialSpeed:        1.5,
        maxInitialSpeed:        4.0,
        speedLevelMultiplier:   0.5
    )

    static func floatingConfig(for type: FloatingObjectType) -> FloatingObjectClassConfig {
        switch type {
        case .light: return lightObject
        case .heavy: return heavyObject
        case .fuel:  return fuelObject
        }
    }

    // MARK: - Floating Object Pixmaps
    //
    // Each entry is (bundle filename, bonus). The bonus is added to the player score
    // when the lander collides with that object. The pixmaps are loaded once at startup
    // via `loadFloatingTextures(...)`, scaled so their longer edge is no greater than
    // the matching max-size below, and a random entry is picked at every spawn.

    static let lightObjects: [(filename: String, bonus: Int)] = [
        ("Leichte_Objekte_Aus_Auswahl.png", 10),
        ("Leichte_Objekte_Buch.png",        10),
        ("Leichte_Objekte_Huhn.png",        10),
        ("Leichte_Objekte_Hut.png",         10),
        ("Leichte_Objekte_Jacke.png",       10),
        ("Leichte_Objekte_Kleeblatt.png",   10),
        ("Leichte_Objekte_Klopömpel.png",   10),
        ("Leichte_Objekte_Luftpumpe.png",   10),
        ("Leichte_Objekte_Regenschirm.png", 10),
        ("Leichte_Objekte_Schuh.png",       10),
    ]

    static let heavyObjects: [(filename: String, bonus: Int)] = [
        ("Schwere_Objekte_auto.png",       0),
        ("Schwere_Objekte_bombe.png",      0),
        ("Schwere_Objekte_dampflok.png",   0),
        ("Schwere_Objekte_mahlstrom.png",  0),
        ("Schwere_Objekte_meteor_01.png",  0),
        ("Schwere_Objekte_meteor_02.png",  0),
        ("Schwere_Objekte_meteor_03.png",  0),
        ("Schwere_Objekte_meteor_04.png",  0),
        ("Schwere_Objekte_meteor_05.png",  0),
    ]

    static let fuelObjects: [(filename: String, bonus: Int)] = [
        ("Fuel.png", 0),
    ]

    /// Scaling factors `s` — pixmaps whose longer edge exceeds this value are
    /// resampled down so the longer edge equals `s`. Smaller pixmaps are left alone.
    static let lightObjectMaxSize: Int = 150/4
    static let heavyObjectMaxSize: Int = 200/4
    static let fuelObjectMaxSize:  Int = 170/4

    // MARK: - Shield Blasters

    /// Number of shield blasters the player starts a fresh game with.
    static let maxShieldBlasters: Int = 3

    /// Maximum reach of the energy ring, in game units (game width is 1000).
    static let shieldBlasterRadius: Float = 200

    /// Full animation length in seconds. The ring grows during the first half
    /// and fades during the second.
    static let shieldBlasterDuration: Float = 0.7

    // MARK: - Demo / Attract Loop

    /// Level the attract-mode demo plays. Level 2 has wind plus floating objects,
    /// so the demo can showcase shield blasters in action.
    static let demoLevel: Int = 2

    /// Maximum runtime of a single demo round before it auto-returns to the logo.
    /// The demo also ends earlier on landing, crash, or tip-over.
    static let demoMaxDuration: Float = 50.0
}
