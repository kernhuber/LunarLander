//
//  Renderer.swift
//  LunarLander
//
//  Complete game logic and Metal 2D rendering for Lunar Lander
//

import Metal
import MetalKit
import simd
import os

// Unified-logging channel so debug messages appear in Console.app,
// Xcode → Window → Devices and Simulators → Open Console, and `log show`.
// Plain `print()` only shows in Xcode's *debug* console.
private let landingLog = Logger(subsystem: "de.kernhuber.LunarLander", category: "landing")

// MARK: - Game Constants

private let mainThrustPower: Float = 3.5
private let sideThrustPower: Float = 2.0
private let mainFuelRate: Float = 8.0
private let sideFuelRate: Float = 4.0
private let maxLandingVSpeed: Float = 2.5
private let maxLandingHSpeed: Float = 2.5

// MARK: - Game State

enum GameState {
    case logo
    case highscores
    case demo
    case playing
    case landed
    case levelTransition
    case crashed
    case tippedOver
    case gameOver
    case enteringName
}

// MARK: - Input State

struct InputState {
    var thrustMain: Bool = false
    var thrustLeft: Bool = false
    var thrustRight: Bool = false
}

// MARK: - Particle

struct Particle {
    var x: Float; var y: Float
    var vx: Float; var vy: Float
    var life: Float; var maxLife: Float
    var r: Float; var g: Float; var b: Float
}

// MARK: - Star

struct Star {
    var x: Float; var y: Float
    var brightness: Float
    var twinkleSpeed: Float
    var twinklePhase: Float
}

// MARK: - Floating Objects

enum FloatingObjectType {
    case light    // grazes the lander, adds bonus to score, then vanishes
    case heavy    // destroys the lander on contact
    case fuel     // refuels the lander on contact, then vanishes
}

struct FloatingObject {
    var type: FloatingObjectType
    var texture: MTLTexture
    var bonus: Int             // score added on light pickup (0 for heavy/fuel)
    var width: Float           // display size in game units (== texture pixel width)
    var height: Float
    var x: Float
    var y: Float
    var vx: Float
    var rotation: Float        // current orientation, radians
    var angularVelocity: Float // radians per second (random, set at spawn)
    var alive: Bool
}

// Short-lived floating text shown at a collision point (e.g. "+10 POINTS").
struct ScorePopup {
    var x: Float
    var y: Float
    var text: String
    var life: Float       // seconds remaining
    let maxLife: Float
}

// Energy ring deployed by the player; sweeps outward and destroys heavy objects within.
struct ActiveShield {
    var x: Float
    var y: Float
    var elapsed: Float    // seconds since deployment
    let duration: Float
    let maxRadius: Float
}

// MARK: - Renderer

class Renderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var trianglePipeline: MTLRenderPipelineState!
    var linePipeline: MTLRenderPipelineState!
    var pointPipeline: MTLRenderPipelineState!

    let gameWidth: Float = 1000.0
    var gameHeight: Float = 750.0
    var pixelsPerMeter: Float = 12.0
    var drawableSize: SIMD2<Float> = SIMD2<Float>(800, 600)

    // Lander dimensions
    let landerW: Float = 28.0
    let landerH: Float = 34.0
    let legSpread: Float = 34.0
    let legHeight: Float = 10.0

    // Game state
    var gameState: GameState = .logo
    var landerX: Float = 0
    var landerY: Float = 0
    var velocityX: Float = 0
    var velocityY: Float = 0
    var fuel: Float = 0
    var initialFuel: Float = 0
    var input = InputState()
    var gameTime: Float = 0
    var tipDirection: Float = 0
    var stateChangeTime: Float = 0

    // Scoring and levels
    var currentLevel: Int = 1
    var totalScore: Int = 0
    var lastLevelScore: Int = 0
    var enteredName: String = ""
    var nameCursorBlink: Float = 0

    // Per-level physics
    var levelGravity: Float = 1.62
    var levelMainThrust: Float = 3.5
    var levelSideThrust: Float = 2.0
    var atmosphereDrag: Float = 0.0
    var windForce: Float = 0.0
    var windBase: Float = 0.0
    var windVariability: Float = 0.0
    var windChangeTimer: Float = 0.0
    var windTargetForce: Float = 0.0

    // Per-level colors
    var skyColor: (r: Double, g: Double, b: Double) = (0.01, 0.01, 0.06)
    var terrainSurface: (r: Float, g: Float, b: Float) = (0.45, 0.42, 0.38)
    var terrainDeep: (r: Float, g: Float, b: Float) = (0.12, 0.11, 0.10)
    var terrainOutline: (r: Float, g: Float, b: Float) = (0.65, 0.6, 0.55)

    // Logo texture
    var logoTexture: MTLTexture?
    var texturePipeline: MTLRenderPipelineState!

    // Demo mode
    var demoMode: Bool = false

    // Touch device flag (set to true on iOS)
    var isTouchDevice: Bool = false

    // State change callback (for music control)
    var onStateChange: ((GameState) -> Void)?

    // Fired when the lander picks up a fuel object (host plays the success sound).
    var onFuelPickup: (() -> Void)?

    // Fired when the lander grazes a light object (host plays the "blurp" sound).
    var onLightPickup: (() -> Void)?

    // Fired when a heavy object is destroyed by a shield blaster (host plays the crash sound).
    var onHeavyDestroyed: (() -> Void)?

    // Fired when the player deploys a shield blaster (host plays the shield sound).
    var onShieldDeployed: (() -> Void)?

    // Loaded floating-object pixmaps, paired with the per-pixmap bonus score.
    // Populated once at startup from GameConfig.lightObjects / heavyObjects / fuelObjects.
    var lightTextures: [(texture: MTLTexture, bonus: Int)] = []
    var heavyTextures: [(texture: MTLTexture, bonus: Int)] = []
    var fuelTextures:  [(texture: MTLTexture, bonus: Int)] = []
    var floatingObjects: [FloatingObject] = []

    // Spawn accumulators for ongoing random spawning during play. Each frame the
    // accumulator gains (rate * dt); when it crosses 1.0, an object spawns. This
    // produces a steady rate that exactly matches GameConfig.floatingConfig(for:).
    var lightSpawnAccumulator: Float = 0
    var heavySpawnAccumulator: Float = 0
    var fuelSpawnAccumulator: Float = 0
    let maxFloatingObjects: Int = 10

    // Floating score popups (one per light-object hit, ~1 second life each).
    var scorePopups: [ScorePopup] = []

    // Lives — decremented on crash/tip; when > 0 player retries the current level.
    let maxLives: Int = 3
    var lives: Int = 3

    // Shield blasters — limited-charge weapon that destroys heavy objects within a radius.
    var shieldsRemaining: Int = 0
    var activeShields: [ActiveShield] = []

    // Terrain
    var terrainPoints: [(Float, Float)] = []
    var landingPadStart: Float = 0
    var landingPadEnd: Float = 0
    var landingPadY: Float = 0

    // Particles and stars
    var particles: [Particle] = []
    var stars: [Star] = []

    // Timing
    var lastUpdateTime: CFTimeInterval = 0

    // Vertex buffer
    var vertexBuffer: MTLBuffer!
    let maxVertices = 131072
    var vertexBufferOffset = 0

    // Track if initial setup done
    var initialSetupDone = false

    @MainActor
    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!

        super.init()

        metalKitView.colorPixelFormat = .bgra8Unorm_srgb
        metalKitView.depthStencilPixelFormat = .invalid
        metalKitView.preferredFramesPerSecond = 60

        guard let library = device.makeDefaultLibrary() else { return nil }
        let vertexFunc = library.makeFunction(name: "vertexShader2D")
        let fragmentFunc = library.makeFunction(name: "fragmentShader2D")
        let starFragFunc = library.makeFunction(name: "starFragmentShader")

        func makePipeline(frag: MTLFunction?) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFunc
            desc.fragmentFunction = frag
            desc.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        trianglePipeline = makePipeline(frag: fragmentFunc)
        linePipeline = makePipeline(frag: fragmentFunc)
        pointPipeline = makePipeline(frag: starFragFunc)
        guard trianglePipeline != nil, linePipeline != nil, pointPipeline != nil else { return nil }

        // Texture pipeline for logo
        let texVertFunc = library.makeFunction(name: "textureVertexShader")
        let texFragFunc = library.makeFunction(name: "textureFragmentShader")
        let texDesc = MTLRenderPipelineDescriptor()
        texDesc.vertexFunction = texVertFunc
        texDesc.fragmentFunction = texFragFunc
        texDesc.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        texDesc.colorAttachments[0].isBlendingEnabled = true
        texDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        texDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        texDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        texDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        texturePipeline = try? device.makeRenderPipelineState(descriptor: texDesc)

        vertexBuffer = device.makeBuffer(length: maxVertices * MemoryLayout<Vertex2D>.stride,
                                         options: .storageModeShared)

        // Load logo texture
        loadLogoTexture()

        // Load floating-object pixmaps from disk.
        lightTextures = loadFloatingTextures(GameConfig.lightObjects, maxSize: GameConfig.lightObjectMaxSize)
        heavyTextures = loadFloatingTextures(GameConfig.heavyObjects, maxSize: GameConfig.heavyObjectMaxSize)
        fuelTextures  = loadFloatingTextures(GameConfig.fuelObjects,  maxSize: GameConfig.fuelObjectMaxSize)
    }

    func loadLogoTexture() {
        guard let url = Bundle.main.url(forResource: "Logo", withExtension: "png") else { return }
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: true,
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        logoTexture = try? loader.newTexture(URL: url, options: options)
    }

    /// Generic pixmap loader. Reads each (filename, bonus) entry from the app bundle,
    /// scales the image down so its longer edge equals `s` if it currently exceeds `s`
    /// (smaller images pass through untouched), and returns the resulting Metal textures
    /// paired with their original bonus values.
    func loadFloatingTextures(_ entries: [(filename: String, bonus: Int)],
                              maxSize s: Int) -> [(MTLTexture, Int)] {
        var result: [(MTLTexture, Int)] = []
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: true,
            .origin: MTKTextureLoader.Origin.topLeft,
        ]

        for entry in entries {
            // Split the filename into base + extension so Bundle.url can find it.
            let (base, ext): (String, String?) = {
                if let dot = entry.filename.lastIndex(of: ".") {
                    let afterDot = entry.filename.index(after: dot)
                    return (String(entry.filename[..<dot]), String(entry.filename[afterDot...]))
                }
                return (entry.filename, nil)
            }()

            guard let url = Bundle.main.url(forResource: base, withExtension: ext) else {
                print("Floating-object texture not found in bundle: \(entry.filename)")
                continue
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                print("Failed to decode pixmap: \(entry.filename)")
                continue
            }

            let w = cgImage.width
            let h = cgImage.height
            let maxDim = max(w, h)

            let finalImage: CGImage
            if maxDim > s {
                let scaleFactor = Double(s) / Double(maxDim)
                let newW = max(1, Int((Double(w) * scaleFactor).rounded()))
                let newH = max(1, Int((Double(h) * scaleFactor).rounded()))
                finalImage = resizeCGImage(cgImage, width: newW, height: newH) ?? cgImage
            } else {
                finalImage = cgImage
            }

            if let tex = try? loader.newTexture(cgImage: finalImage, options: options) {
                result.append((tex, entry.bonus))
            }
        }
        return result
    }

    private func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let cs = colorSpace else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: cs, bitmapInfo: bitmapInfo) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Game Setup

    func startNewGame() {
        demoMode = false
        currentLevel = 1
        totalScore = 0
        lastLevelScore = 0
        lives = maxLives
        setupLevel()
        gameState = .playing
        onStateChange?(.playing)
    }

    func startGameAtLevel(_ level: Int) {
        demoMode = false
        currentLevel = max(1, min(level, 9))
        totalScore = 0
        lastLevelScore = 0
        lives = maxLives
        setupLevel()
        gameState = .playing
        onStateChange?(.playing)
    }

    /// Retry the current level after a crash. Caller is responsible for waiting
    /// out the explosion animation (caller-side cooldown enforced by view controllers).
    func retryCurrentLevel() {
        guard (gameState == .crashed || gameState == .tippedOver) && lives > 0 else { return }
        setupLevel()
        gameState = .playing
        onStateChange?(.playing)
    }

    func setupDemo() {
        demoMode = true
        currentLevel = GameConfig.demoLevel
        totalScore = 0
        lastLevelScore = 0
        setupLevel()
        gameState = .demo
        stateChangeTime = gameTime
    }

    func setupNextLevel() {
        currentLevel += 1
        setupLevel()
        gameState = .playing
        onStateChange?(.playing)
    }

    func setupLevel() {
        configureLevelPhysics()
        generateTerrain()

        let padCenter = (landingPadStart + landingPadEnd) / 2.0
        if padCenter > gameWidth / 2.0 {
            landerX = gameWidth * Float.random(in: 0.1...0.3)
        } else {
            landerX = gameWidth * Float.random(in: 0.7...0.9)
        }
        landerY = gameHeight - 60

        velocityX = 0
        velocityY = 0
        stateChangeTime = gameTime
        particles = []
        scorePopups = []
        // Shields refresh on every level — they are a per-level resource, not per-run.
        shieldsRemaining = GameConfig.maxShieldBlasters
        activeShields = []
        input = InputState()
        spawnFloatingObjects()

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
        fuel = initialFuel
    }

    func configureLevelPhysics() {
        switch currentLevel {
        case 1:
            levelGravity = 1.62
            atmosphereDrag = 0.0
            windBase = 0.0
            windVariability = 0.0
        case 2:
            levelGravity = 2.0
            atmosphereDrag = 0.3
            windBase = 0.3
            windVariability = 0.0
        case 3:
            levelGravity = 2.5
            atmosphereDrag = 0.5
            windBase = 0.5
            windVariability = 0.3
        case 4:
            levelGravity = 3.2
            atmosphereDrag = 0.7
            windBase = 0.7
            windVariability = 0.5
        case 5:
            levelGravity = 4.0
            atmosphereDrag = 0.9
            windBase = 0.9
            windVariability = 0.7
        default:
            levelGravity = min(4.0 + Float(currentLevel - 5) * 0.5, 7.0)
            atmosphereDrag = 1.0
            windBase = 1.2
            windVariability = 0.9
        }

        // Scale thrust to maintain playability (thrust must exceed gravity)
        // Level 1 ratio: 3.5 / 1.62 = 2.16x. Higher levels get tighter ratio (harder).
        let thrustRatio = max(1.4, 2.16 - Float(currentLevel - 1) * 0.12)
        levelMainThrust = levelGravity * thrustRatio
        levelSideThrust = levelMainThrust * (sideThrustPower / mainThrustPower)

        // Randomize wind direction, set initial force
        let windSign: Float = Bool.random() ? 1.0 : -1.0
        windForce = windBase * windSign
        windTargetForce = windForce
        windChangeTimer = 0.0

        // Level colors
        switch currentLevel {
        case 1: // Moon — dark sky, grey rock
            skyColor = (0.01, 0.01, 0.06)
            terrainSurface = (0.45, 0.42, 0.38)
            terrainDeep = (0.12, 0.11, 0.10)
            terrainOutline = (0.65, 0.6, 0.55)
        case 2: // Mars — dark red sky, rust rock
            skyColor = (0.06, 0.01, 0.01)
            terrainSurface = (0.55, 0.25, 0.12)
            terrainDeep = (0.18, 0.06, 0.03)
            terrainOutline = (0.7, 0.35, 0.18)
        case 3: // Venus — murky amber sky, dark volcanic rock
            skyColor = (0.08, 0.05, 0.01)
            terrainSurface = (0.35, 0.30, 0.15)
            terrainDeep = (0.10, 0.08, 0.04)
            terrainOutline = (0.55, 0.45, 0.20)
        case 4: // Titan — deep blue-green sky, icy dark terrain
            skyColor = (0.01, 0.04, 0.08)
            terrainSurface = (0.25, 0.35, 0.42)
            terrainDeep = (0.06, 0.10, 0.14)
            terrainOutline = (0.35, 0.50, 0.60)
        case 5: // Io — yellow-green volcanic sky, sulfur terrain
            skyColor = (0.06, 0.06, 0.01)
            terrainSurface = (0.50, 0.45, 0.10)
            terrainDeep = (0.15, 0.12, 0.02)
            terrainOutline = (0.70, 0.60, 0.15)
        default: // Deep space planets — purple alien sky, alien rock
            let cycle = (currentLevel - 6) % 4
            switch cycle {
            case 0: // Purple alien
                skyColor = (0.04, 0.01, 0.08)
                terrainSurface = (0.40, 0.20, 0.50)
                terrainDeep = (0.12, 0.05, 0.15)
                terrainOutline = (0.55, 0.30, 0.65)
            case 1: // Crimson
                skyColor = (0.08, 0.02, 0.02)
                terrainSurface = (0.50, 0.15, 0.15)
                terrainDeep = (0.15, 0.04, 0.04)
                terrainOutline = (0.65, 0.20, 0.20)
            case 2: // Emerald
                skyColor = (0.01, 0.06, 0.03)
                terrainSurface = (0.15, 0.45, 0.25)
                terrainDeep = (0.04, 0.14, 0.07)
                terrainOutline = (0.20, 0.60, 0.35)
            default: // Frozen blue
                skyColor = (0.02, 0.03, 0.10)
                terrainSurface = (0.30, 0.38, 0.55)
                terrainDeep = (0.08, 0.10, 0.18)
                terrainOutline = (0.40, 0.50, 0.70)
            }
        }
    }

    // MARK: - Scoring

    func calculateLevelScore() -> Int {
        let fuelPercent = fuel / max(initialFuel, 1.0)
        let fuelBonus = fuelPercent * 500.0
        let vFactor = 1.0 - (min(abs(velocityY), maxLandingVSpeed) / maxLandingVSpeed)
        let vBonus = vFactor * 300.0
        let hFactor = 1.0 - (min(abs(velocityX), maxLandingHSpeed) / maxLandingHSpeed)
        let hBonus = hFactor * 200.0
        let base: Float = 100.0
        let multiplier = 1.0 + Float(currentLevel - 1) * 0.2
        return Int((base + fuelBonus + vBonus + hBonus) * multiplier)
    }

    // MARK: - Name Entry

    func appendNameCharacter(_ c: Character) {
        guard enteredName.count < 10 else { return }
        enteredName.append(c)
    }

    func deleteNameCharacter() {
        guard !enteredName.isEmpty else { return }
        enteredName.removeLast()
    }

    func confirmName() {
        let name = enteredName.isEmpty ? "PLAYER" : enteredName
        HighscoreManager.shared.addEntry(name: name, score: totalScore, level: currentLevel)
        enteredName = ""
        gameState = .highscores
        stateChangeTime = gameTime
        onStateChange?(.highscores)
    }

    // MARK: - Terrain Generation

    func generateTerrain() {
        terrainPoints = []
        let numSegments = 80
        let segWidth = gameWidth / Float(numSegments)
        let baseH = gameHeight * 0.18
        let maxVar = gameHeight * 0.22

        let padSegStart = Int.random(in: 10...(numSegments - 15))
        let padSegEnd = padSegStart + 5

        var heights: [Float] = []
        for i in 0...numSegments {
            if i >= padSegStart && i <= padSegEnd {
                heights.append(0)
            } else {
                let n = Float(i) / Float(numSegments)
                let v1 = sin(n * .pi * 2.3) * maxVar * 0.35
                let v2 = sin(n * .pi * 5.7) * maxVar * 0.25
                let v3 = sin(n * .pi * 11.3) * maxVar * 0.15
                let rnd = Float.random(in: -maxVar * 0.12...maxVar * 0.12)
                heights.append(baseH + v1 + v2 + v3 + rnd)
            }
        }

        let leftH = padSegStart > 0 ? heights[padSegStart - 1] : baseH
        let rightH = padSegEnd < numSegments ? heights[padSegEnd + 1] : baseH
        // Clamp to the same minimum floor that the later pass enforces on all heights,
        // otherwise the floor raises the pad-segment terrain while landingPadY stays
        // lower, drawing the pad rectangle under the visible terrain.
        let padH = max(min(leftH, rightH) * 0.9, gameHeight * 0.05)
        for i in padSegStart...padSegEnd { heights[i] = padH }

        for d in 1...3 {
            let t = Float(d) / 4.0
            let li = padSegStart - d
            if li >= 0 { heights[li] = heights[li] * (1 - t) + padH * t }
            let ri = padSegEnd + d
            if ri <= numSegments { heights[ri] = heights[ri] * (1 - t) + padH * t }
        }

        for i in 0...numSegments {
            heights[i] = max(heights[i], gameHeight * 0.05)
        }

        for i in 0...numSegments {
            terrainPoints.append((Float(i) * segWidth, heights[i]))
        }

        landingPadStart = Float(padSegStart) * segWidth
        landingPadEnd = Float(padSegEnd) * segWidth
        landingPadY = padH
    }

    func generateStars() {
        stars = []
        for _ in 0..<200 {
            stars.append(Star(
                x: Float.random(in: 0...gameWidth),
                y: Float.random(in: gameHeight * 0.35...gameHeight),
                brightness: Float.random(in: 0.3...1.0),
                twinkleSpeed: Float.random(in: 0.5...3.0),
                twinklePhase: Float.random(in: 0...Float.pi * 2.0)
            ))
        }
    }

    // MARK: - Game Update

    func update(dt: Float) {
        gameTime += dt
        updateScorePopups(dt: dt)
        updateShields(dt: dt)

        switch gameState {
        case .logo:
            if gameTime - stateChangeTime >= 7.0 {
                gameState = .highscores
                stateChangeTime = gameTime
            }

        case .highscores:
            if gameTime - stateChangeTime >= 7.0 {
                setupDemo()
            }

        case .demo:
            updatePlaying(dt: dt)
            // Check if lander landed or crashed during demo, or time expired
            if gameState == .landed || gameState == .crashed || gameState == .tippedOver
                || gameTime - stateChangeTime >= GameConfig.demoMaxDuration {
                demoMode = false
                gameState = .logo
                stateChangeTime = gameTime
                onStateChange?(.logo)
            }

        case .playing:
            updatePlaying(dt: dt)

        case .landed:
            updateParticles(dt: dt)
            if gameTime - stateChangeTime >= 1.5 {
                lastLevelScore = calculateLevelScore()
                totalScore += lastLevelScore
                gameState = .levelTransition
                stateChangeTime = gameTime
            }

        case .levelTransition:
            if gameTime - stateChangeTime >= 2.0 {
                setupNextLevel()
            }

        case .crashed, .tippedOver:
            updateParticles(dt: dt)
            // Only auto-transition to gameOver when the player has no lives left.
            // If lives remain, hold this state until the host calls retryCurrentLevel().
            if lives <= 0 && gameTime - stateChangeTime >= 2.5 {
                gameState = .gameOver
                stateChangeTime = gameTime
            }

        case .gameOver:
            if gameTime - stateChangeTime >= 2.0 {
                if HighscoreManager.shared.qualifies(score: totalScore) {
                    gameState = .enteringName
                    stateChangeTime = gameTime
                    enteredName = ""
                    nameCursorBlink = 0
                    onStateChange?(.enteringName)
                } else {
                    gameState = .logo
                    stateChangeTime = gameTime
                    onStateChange?(.logo)
                }
            }

        case .enteringName:
            nameCursorBlink += dt
        }
    }

    func updatePlaying(dt: Float) {
        if demoMode { updateDemoAI() }

        velocityY -= levelGravity * dt

        if input.thrustMain && fuel > 0 {
            velocityY += levelMainThrust * dt
            fuel -= mainFuelRate * dt
            spawnThrustParticles(direction: .main, dt: dt)
        }
        if input.thrustRight && fuel > 0 {
            velocityX += levelSideThrust * dt
            fuel -= sideFuelRate * dt
            spawnThrustParticles(direction: .right, dt: dt)
        }
        if input.thrustLeft && fuel > 0 {
            velocityX -= levelSideThrust * dt
            fuel -= sideFuelRate * dt
            spawnThrustParticles(direction: .left, dt: dt)
        }
        fuel = max(fuel, 0)

        // Atmospheric drag on horizontal movement
        velocityX *= (1.0 - atmosphereDrag * dt)

        // Wind force
        velocityX += windForce * dt

        // Update variable wind
        if windVariability > 0 {
            windChangeTimer += dt
            if windChangeTimer >= 2.0 {
                windChangeTimer = 0
                windTargetForce = windBase * Float.random(in: -1.0...1.0) * (1.0 + windVariability)
            }
            windForce += (windTargetForce - windForce) * dt * 0.8
        }

        landerX += velocityX * pixelsPerMeter * dt
        landerY += velocityY * pixelsPerMeter * dt

        if landerX < 0 { landerX += gameWidth }
        if landerX > gameWidth { landerX -= gameWidth }

        checkCollision()
        updateFloatingObjects(dt: dt)
        checkFloatingCollisions()
        updateParticles(dt: dt)
    }

    func updateScorePopups(dt: Float) {
        for i in scorePopups.indices {
            scorePopups[i].life -= dt
            // Drift upward slightly so the popup looks alive.
            scorePopups[i].y += 30.0 * dt
        }
        scorePopups.removeAll { $0.life <= 0 }
    }

    func updateDemoAI() {
        let padCenter = (landingPadStart + landingPadEnd) / 2.0
        let dx = padCenter - landerX
        let altitude = (landerY - landerH / 2.0 - legHeight - terrainHeightAt(x: landerX)) / pixelsPerMeter
        let vSpeed = -velocityY  // positive = descending
        let hSpeed = velocityX

        // Shield blaster: fire when any heavy is closer than 50 game units (simple
        // Euclidean distance to the heavy's center). Reactive but reliable.
        if shieldsRemaining > 0 && activeShields.isEmpty {
            for obj in floatingObjects where obj.alive && obj.type == .heavy {
                let dx = obj.x - landerX
                let dy = obj.y - landerY
                let distance = sqrt(dx * dx + dy * dy)
                if distance < 50 {
                    deployShieldBlaster()
                    break
                }
            }
        }

        // Horizontal: proportional target velocity toward the pad, with a deadband
        // around the desired speed so the AI does not jitter the side thrusters.
        let dxMeters = dx / pixelsPerMeter
        let hTarget = max(min(dxMeters * 0.4, 3.0), -3.0)
        let hError = hTarget - hSpeed
        let hDeadband: Float = 0.5
        if hError > hDeadband {
            input.thrustRight = true
            input.thrustLeft = false
        } else if hError < -hDeadband {
            input.thrustLeft = true
            input.thrustRight = false
        } else {
            input.thrustLeft = false
            input.thrustRight = false
        }

        // Vertical: target descent rate by altitude band, with hysteresis on thrustMain
        // so a brief overshoot does not keep the engine pinned. Wider deadband at altitude,
        // tighter near touchdown for a controlled final approach.
        let targetV: Float
        let vDeadband: Float
        if altitude > 40 {
            targetV = 3.0; vDeadband = 0.6
        } else if altitude > 15 {
            targetV = 1.8; vDeadband = 0.5
        } else if altitude > 5 {
            targetV = 1.0; vDeadband = 0.35
        } else {
            targetV = 0.6; vDeadband = 0.25
        }
        if vSpeed > targetV + vDeadband {
            input.thrustMain = true
        } else if vSpeed < targetV - vDeadband {
            input.thrustMain = false
        }
        // else: keep previous thrustMain (hysteresis band)
    }

    enum ThrustDirection { case main, left, right }

    func spawnThrustParticles(direction: ThrustDirection, dt: Float) {
        let count = max(1, Int(dt * 150))
        for _ in 0..<count {
            var p = Particle(x: landerX, y: landerY, vx: 0, vy: 0,
                             life: Float.random(in: 0.15...0.5), maxLife: 0.5,
                             r: 1, g: 0.8, b: 0.2)
            switch direction {
            case .main:
                p.x = landerX + Float.random(in: -5...5)
                p.y = landerY - landerH / 2.0 - legHeight
                p.vx = Float.random(in: -40...40)
                p.vy = Float.random(in: -180 ... -60)
                p.g = Float.random(in: 0.3...0.9)
                p.b = Float.random(in: 0.0...0.3)
            case .left:
                p.x = landerX + landerW / 2.0 + 3
                p.y = landerY + Float.random(in: -3...3)
                p.vx = Float.random(in: 60...160)
                p.vy = Float.random(in: -25...25)
                p.g = Float.random(in: 0.3...0.9)
                p.b = Float.random(in: 0.0...0.3)
            case .right:
                p.x = landerX - landerW / 2.0 - 3
                p.y = landerY + Float.random(in: -3...3)
                p.vx = Float.random(in: -160 ... -60)
                p.vy = Float.random(in: -25...25)
                p.g = Float.random(in: 0.3...0.9)
                p.b = Float.random(in: 0.0...0.3)
            }
            particles.append(p)
        }
    }

    func spawnExplosionParticles() {
        spawnExplosionParticles(atX: landerX, y: landerY)
    }

    func spawnExplosionParticles(atX cx: Float, y cy: Float) {
        for _ in 0..<300 {
            let angle = Float.random(in: 0...Float.pi * 2.0)
            let speed = Float.random(in: 40...300)
            particles.append(Particle(
                x: cx + Float.random(in: -12...12),
                y: cy + Float.random(in: -12...12),
                vx: cos(angle) * speed, vy: sin(angle) * speed,
                life: Float.random(in: 0.5...2.5), maxLife: 2.5,
                r: Float.random(in: 0.8...1), g: Float.random(in: 0.2...0.8), b: Float.random(in: 0.0...0.2)))
        }
        for _ in 0..<80 {
            let angle = Float.random(in: 0...Float.pi * 2.0)
            let speed = Float.random(in: 60...200)
            particles.append(Particle(
                x: cx + Float.random(in: -5...5),
                y: cy + Float.random(in: -5...5),
                vx: cos(angle) * speed, vy: sin(angle) * speed,
                life: Float.random(in: 0.3...1.2), maxLife: 1.2,
                r: 1, g: 1, b: Float.random(in: 0.7...1)))
        }
    }

    // MARK: - Shield Blasters

    /// Deploy a shield blaster if any remain and the player is actively playing.
    /// The shield expands from the ship's current position; objects destroyed by it
    /// are handled per-frame in `updateShields(dt:)`.
    func deployShieldBlaster() {
        guard gameState == .playing && shieldsRemaining > 0 else { return }
        shieldsRemaining -= 1
        activeShields.append(ActiveShield(
            x: landerX, y: landerY,
            elapsed: 0,
            duration: GameConfig.shieldBlasterDuration,
            maxRadius: GameConfig.shieldBlasterRadius
        ))
        onShieldDeployed?()
    }

    /// Tick every active shield, expand its radius, and destroy any heavy objects
    /// caught in the sweep. The animation continues independently of game state.
    func updateShields(dt: Float) {
        guard !activeShields.isEmpty else { return }

        for i in activeShields.indices {
            activeShields[i].elapsed += dt
            let currentRadius = currentShieldRadius(for: activeShields[i])
            let cx = activeShields[i].x
            let cy = activeShields[i].y
            let r2 = currentRadius * currentRadius

            for j in floatingObjects.indices where floatingObjects[j].alive {
                guard floatingObjects[j].type == .heavy else { continue }
                let dx = floatingObjects[j].x - cx
                let dy = floatingObjects[j].y - cy
                if dx * dx + dy * dy <= r2 {
                    spawnExplosionParticles(atX: floatingObjects[j].x, y: floatingObjects[j].y)
                    floatingObjects[j].alive = false
                    onHeavyDestroyed?()
                }
            }
        }

        activeShields.removeAll { $0.elapsed >= $0.duration }
        floatingObjects.removeAll { !$0.alive }
    }

    /// Linear growth during the first half, hold-and-fade during the second.
    private func currentShieldRadius(for shield: ActiveShield) -> Float {
        let half = shield.duration * 0.5
        if shield.elapsed < half {
            return shield.maxRadius * (shield.elapsed / half)
        } else {
            return shield.maxRadius
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

    // MARK: - Collision Detection

    func checkCollision() {
        let footY = landerY - landerH / 2.0 - legHeight
        let leftFoot = landerX - legSpread / 2.0
        let rightFoot = landerX + legSpread / 2.0

        let tCenter = terrainHeightAt(x: landerX)
        let tLeft = terrainHeightAt(x: leftFoot)
        let tRight = terrainHeightAt(x: rightFoot)
        let maxT = max(tCenter, max(tLeft, tRight))

        if footY <= maxT {
            let absVY = abs(velocityY)
            let absVX = abs(velocityX)
            let onPad = leftFoot >= landingPadStart && rightFoot <= landingPadEnd

            // Debug: log every touchdown decision so we can diagnose
            // "looked-fine-but-crashed" cases. Uses unified logging so the message
            // appears in Console.app, the Devices-and-Simulators device console,
            // and `log show` — not just Xcode's debug console.
            let landMsg = String(format:
                "[LAND] footY=%.1f maxT=%.1f onPad=%@ leftFoot=%.1f rightFoot=%.1f " +
                "padStart=%.1f padEnd=%.1f vY=%.3f vX=%.3f absVY=%.3f absVX=%.3f " +
                "maxVS=%.2f maxHS=%.2f legSpread=%.1f",
                footY, maxT, onPad ? "YES" : "NO",
                leftFoot, rightFoot,
                landingPadStart, landingPadEnd,
                velocityY, velocityX, absVY, absVX,
                maxLandingVSpeed, maxLandingHSpeed,
                legSpread)
            // Notice-level so it's visible in Console.app and `log show` without extra flags;
            // .info would be hidden unless --info is passed.
            landingLog.notice("\(landMsg, privacy: .public)")

            if onPad && absVY <= maxLandingVSpeed && absVX <= maxLandingHSpeed {
                gameState = .landed
                stateChangeTime = gameTime
                landerY = landingPadY + landerH / 2.0 + legHeight
                velocityX = 0; velocityY = 0
                onStateChange?(.landed)
            } else if absVY <= maxLandingVSpeed && absVX > maxLandingHSpeed {
                gameState = .tippedOver
                stateChangeTime = gameTime
                tipDirection = velocityX > 0 ? 1.0 : -1.0
                velocityX = 0; velocityY = 0
                landerY = maxT + landerH / 2.0 + legHeight
                if !demoMode { lives = max(lives - 1, 0) }
                onStateChange?(.tippedOver)
            } else {
                gameState = .crashed
                stateChangeTime = gameTime
                spawnExplosionParticles()
                velocityX = 0; velocityY = 0
                if !demoMode { lives = max(lives - 1, 0) }
                onStateChange?(.crashed)
            }
        }

        if landerY < -50 {
            gameState = .crashed
            stateChangeTime = gameTime
            spawnExplosionParticles()
            if !demoMode { lives = max(lives - 1, 0) }
            onStateChange?(.crashed)
        }
    }

    // MARK: - Floating Objects

    func spawnFloatingObjects() {
        floatingObjects = []
        lightSpawnAccumulator = 0
        heavySpawnAccumulator = 0
        fuelSpawnAccumulator = 0

        // Seed the scene with a couple of light objects so the level does not start empty.
        for _ in 0..<2 {
            spawnObject(of: .light, atEdge: false)
        }
    }

    private func texturePool(for type: FloatingObjectType) -> [(texture: MTLTexture, bonus: Int)] {
        switch type {
        case .light: return lightTextures
        case .heavy: return heavyTextures
        case .fuel:  return fuelTextures
        }
    }

    /// Spawn a single object of the given type. When `atEdge` is true the object enters
    /// from off-screen with velocity directed inward; otherwise it appears at a random
    /// on-screen position. Initial speed magnitude is drawn from the per-class config,
    /// scaled by the current level. The pixmap is chosen randomly from the matching pool.
    private func spawnObject(of type: FloatingObjectType, atEdge: Bool) {
        guard floatingObjects.count < maxFloatingObjects else { return }
        let pool = texturePool(for: type)
        guard let pick = pool.randomElement() else { return }

        // Display size mirrors the loaded texture's pixel dimensions (1:1 to game units).
        let width = Float(pick.texture.width)
        let height = Float(pick.texture.height)

        let cfg = GameConfig.floatingConfig(for: type)
        let scale = max(cfg.speedLevelMultiplier * Float(currentLevel), 0.01)
        let speedMin = cfg.minInitialSpeed * scale
        let speedMax = max(cfg.maxInitialSpeed * scale, speedMin + 0.01)
        let speedMagnitude = Float.random(in: speedMin...speedMax)

        let y = Float.random(in: gameHeight * 0.30 ... gameHeight * 0.80)

        let x: Float
        let vx: Float
        if atEdge {
            let fromLeft = Bool.random()
            // Push the spawn farther off-screen so larger pixmaps fully enter from outside.
            let margin = max(width * 0.5 + 10, 25)
            x = fromLeft ? -margin : gameWidth + margin
            vx = fromLeft ? speedMagnitude : -speedMagnitude
        } else {
            x = Float.random(in: 80 ... (gameWidth - 80))
            vx = Bool.random() ? speedMagnitude : -speedMagnitude
        }

        let rotation = Float.random(in: 0...(2.0 * .pi))
        let angularVelocity = Float.random(in: -3.0...3.0)

        floatingObjects.append(FloatingObject(
            type: type, texture: pick.texture, bonus: pick.bonus,
            width: width, height: height,
            x: x, y: y, vx: vx,
            rotation: rotation, angularVelocity: angularVelocity, alive: true
        ))
    }

    func updateFloatingObjects(dt: Float) {
        // Light wind influence so individual initial speeds remain visible. The lander
        // still feels full wind force; floating objects only get a gentle nudge.
        let response: Float = 0.18
        for i in floatingObjects.indices where floatingObjects[i].alive {
            floatingObjects[i].vx += (windForce - floatingObjects[i].vx) * response * dt
            floatingObjects[i].x += floatingObjects[i].vx * pixelsPerMeter * dt
            floatingObjects[i].rotation += floatingObjects[i].angularVelocity * dt
            // Off-screen: discard.
            if floatingObjects[i].x < -60 || floatingObjects[i].x > gameWidth + 60 {
                floatingObjects[i].alive = false
            }
        }
        floatingObjects.removeAll { !$0.alive }

        tickRandomSpawning(dt: dt)
    }

    private func tickRandomSpawning(dt: Float) {
        let level = Float(currentLevel)

        // Accumulator pattern: rate = spawnsPerSecond * spawnLevelMultiplier * level.
        // Each unit accumulated emits one spawn.
        let lc = GameConfig.lightObject
        lightSpawnAccumulator += lc.spawnsPerSecond * lc.spawnLevelMultiplier * level * dt
        while lightSpawnAccumulator >= 1.0 {
            spawnObject(of: .light, atEdge: true)
            lightSpawnAccumulator -= 1.0
        }

        let hc = GameConfig.heavyObject
        heavySpawnAccumulator += hc.spawnsPerSecond * hc.spawnLevelMultiplier * level * dt
        while heavySpawnAccumulator >= 1.0 {
            spawnObject(of: .heavy, atEdge: true)
            heavySpawnAccumulator -= 1.0
        }

        let fc = GameConfig.fuelObject
        fuelSpawnAccumulator += fc.spawnsPerSecond * fc.spawnLevelMultiplier * level * dt
        if fuelSpawnAccumulator >= 1.0 {
            let alreadyHasFuel = floatingObjects.contains { $0.alive && $0.type == .fuel }
            if alreadyHasFuel {
                // Hold the accumulator at 1.0 so a new fuel appears as soon as the
                // current one leaves the screen, instead of silently losing turns.
                fuelSpawnAccumulator = 1.0
            } else {
                spawnObject(of: .fuel, atEdge: true)
                fuelSpawnAccumulator -= 1.0
            }
        }
    }

    func checkFloatingCollisions() {
        let lw = landerW * 0.5
        let lh = landerH * 0.5 + legHeight * 0.5
        let lcx = landerX
        let lcy = landerY - legHeight * 0.5   // bias hitbox slightly down to include legs

        for i in floatingObjects.indices where floatingObjects[i].alive {
            let obj = floatingObjects[i]
            // Use a hit box smaller than the rendered sprite so transparent corners do
            // not register as collisions. 60% of the rendered size is a reasonable fit
            // for the visible silhouettes.
            let hitFactor: Float = 0.6
            let hw = obj.width * 0.5 * hitFactor
            let hh = obj.height * 0.5 * hitFactor
            let ox = obj.x
            let oy = obj.y

            // AABB overlap
            if abs(ox - lcx) > (hw + lw) { continue }
            if abs(oy - lcy) > (hh + lh) { continue }

            switch obj.type {
            case .heavy:
                gameState = .crashed
                stateChangeTime = gameTime
                spawnExplosionParticles()
                velocityX = 0; velocityY = 0
                floatingObjects[i].alive = false
                if !demoMode { lives = max(lives - 1, 0) }
                onStateChange?(.crashed)
                return

            case .fuel:
                fuel = min(fuel + initialFuel * 0.4, initialFuel)
                floatingObjects[i].alive = false
                onFuelPickup?()

            case .light:
                // Graze: object is destroyed, lander velocity unaffected, score gains `bonus`.
                floatingObjects[i].alive = false
                totalScore += obj.bonus
                scorePopups.append(ScorePopup(
                    x: ox, y: oy, text: "+\(obj.bonus) POINTS", life: 1.0, maxLife: 1.0
                ))
                onLightPickup?()
            }
        }

        floatingObjects.removeAll { !$0.alive }
    }

    func terrainHeightAt(x: Float) -> Float {
        guard terrainPoints.count > 1 else { return 0 }
        var wx = x
        if wx < 0 { wx += gameWidth }
        if wx > gameWidth { wx -= gameWidth }
        for i in 0..<(terrainPoints.count - 1) {
            let (x0, y0) = terrainPoints[i]
            let (x1, y1) = terrainPoints[i + 1]
            if wx >= x0 && wx <= x1 {
                let t = (wx - x0) / max(x1 - x0, 0.001)
                return y0 + (y1 - y0) * t
            }
        }
        return terrainPoints.last?.1 ?? 0
    }

    // MARK: - Drawing

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = lastUpdateTime == 0 ? Float(1.0 / 60.0) : Float(now - lastUpdateTime)
        lastUpdateTime = now
        update(dt: min(dt, 1.0 / 30.0))

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let rpd = view.currentRenderPassDescriptor else { return }

        rpd.colorAttachments[0].clearColor = MTLClearColor(red: skyColor.r, green: skyColor.g, blue: skyColor.b, alpha: 1.0)
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        vertexBufferOffset = 0
        var u = Uniforms2D(viewportSize: drawableSize)

        switch gameState {
        case .logo:
            drawStars(enc: enc, u: &u)
            drawLogo(enc: enc, u: &u)

        case .highscores:
            drawStars(enc: enc, u: &u)
            drawHighscoreScreen(enc: enc, u: &u)

        case .demo:
            drawStars(enc: enc, u: &u)
            drawTerrain(enc: enc, u: &u)
            drawLandingPad(enc: enc, u: &u)
            drawParticles(enc: enc, u: &u)
            drawLander(enc: enc, u: &u)
            drawDemoOverlay(enc: enc, u: &u)

        case .playing:
            drawStars(enc: enc, u: &u)
            drawTerrain(enc: enc, u: &u)
            drawLandingPad(enc: enc, u: &u)
            drawParticles(enc: enc, u: &u)
            drawLander(enc: enc, u: &u)
            drawHUD(enc: enc, u: &u)

        case .landed:
            drawStars(enc: enc, u: &u)
            drawTerrain(enc: enc, u: &u)
            drawLandingPad(enc: enc, u: &u)
            drawParticles(enc: enc, u: &u)
            drawLander(enc: enc, u: &u)
            drawHUD(enc: enc, u: &u)
            drawLandedMessage(enc: enc, u: &u)

        case .levelTransition:
            drawStars(enc: enc, u: &u)
            drawTerrain(enc: enc, u: &u)
            drawLandingPad(enc: enc, u: &u)
            drawLander(enc: enc, u: &u)
            drawHUD(enc: enc, u: &u)
            drawLevelTransition(enc: enc, u: &u)

        case .crashed:
            drawStars(enc: enc, u: &u)
            drawTerrain(enc: enc, u: &u)
            drawLandingPad(enc: enc, u: &u)
            drawParticles(enc: enc, u: &u)
            drawHUD(enc: enc, u: &u)
            drawCrashedMessage(enc: enc, u: &u)

        case .tippedOver:
            drawStars(enc: enc, u: &u)
            drawTerrain(enc: enc, u: &u)
            drawLandingPad(enc: enc, u: &u)
            drawParticles(enc: enc, u: &u)
            drawLander(enc: enc, u: &u)
            drawHUD(enc: enc, u: &u)
            drawTippedOverMessage(enc: enc, u: &u)

        case .gameOver:
            drawStars(enc: enc, u: &u)
            drawTerrain(enc: enc, u: &u)
            drawLandingPad(enc: enc, u: &u)
            drawParticles(enc: enc, u: &u)
            drawHUD(enc: enc, u: &u)
            drawGameOverMessage(enc: enc, u: &u)

        case .enteringName:
            drawStars(enc: enc, u: &u)
            drawNameEntryScreen(enc: enc, u: &u)
        }

        enc.endEncoding()
        if let drawable = view.currentDrawable { commandBuffer.present(drawable) }
        commandBuffer.commit()
    }

    // MARK: - Drawing Helpers

    func gx(_ x: Float) -> Float { return x / gameWidth * drawableSize.x }
    func gy(_ y: Float) -> Float { return y / gameHeight * drawableSize.y }

    func v(_ x: Float, _ y: Float, _ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0) -> Vertex2D {
        return Vertex2D(position: SIMD2<Float>(gx(x), gy(y)), color: SIMD4<Float>(r, g, b, a))
    }

    func upload(encoder: MTLRenderCommandEncoder, vertices: [Vertex2D],
                uniforms: inout Uniforms2D, type: MTLPrimitiveType) {
        guard !vertices.isEmpty else { return }
        let byteSize = vertices.count * MemoryLayout<Vertex2D>.stride
        let totalBufferSize = maxVertices * MemoryLayout<Vertex2D>.stride
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

    // MARK: - Draw Stars

    func drawStars(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        var verts: [Vertex2D] = []
        for s in stars {
            let twinkle = (sin(gameTime * s.twinkleSpeed + s.twinklePhase) + 1) / 2
            let a = s.brightness * (0.4 + 0.6 * twinkle)
            verts.append(v(s.x, s.y, 0.9, 0.9, 1.0, a))
        }
        upload(encoder: enc, vertices: verts, uniforms: &u, type: .point)
    }

    // MARK: - Draw Terrain

    func drawTerrain(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        var tris: [Vertex2D] = []
        let sr = terrainSurface.r, sg = terrainSurface.g, sb = terrainSurface.b
        let dr = terrainDeep.r, dg = terrainDeep.g, db = terrainDeep.b

        for i in 0..<(terrainPoints.count - 1) {
            let (x0, y0) = terrainPoints[i]
            let (x1, y1) = terrainPoints[i + 1]
            tris.append(v(x0, y0, sr, sg, sb))
            tris.append(v(x1, y1, sr, sg, sb))
            tris.append(v(x0, 0, dr, dg, db))
            tris.append(v(x1, y1, sr, sg, sb))
            tris.append(v(x1, 0, dr, dg, db))
            tris.append(v(x0, 0, dr, dg, db))
        }
        upload(encoder: enc, vertices: tris, uniforms: &u, type: .triangle)

        var lines: [Vertex2D] = []
        let olr = terrainOutline.r, olg = terrainOutline.g, olb = terrainOutline.b
        for i in 0..<(terrainPoints.count - 1) {
            let (x0, y0) = terrainPoints[i]
            let (x1, y1) = terrainPoints[i + 1]
            lines.append(v(x0, y0, olr, olg, olb))
            lines.append(v(x1, y1, olr, olg, olb))
        }
        upload(encoder: enc, vertices: lines, uniforms: &u, type: .line)
    }

    // MARK: - Draw Landing Pad

    func drawLandingPad(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let padH: Float = 4.0
        let top = landingPadY + padH
        let bot = landingPadY

        var tris: [Vertex2D] = []
        tris.append(v(landingPadStart, top, 0.15, 0.75, 0.15))
        tris.append(v(landingPadEnd, top, 0.15, 0.75, 0.15))
        tris.append(v(landingPadStart, bot, 0.08, 0.45, 0.08))
        tris.append(v(landingPadEnd, top, 0.15, 0.75, 0.15))
        tris.append(v(landingPadEnd, bot, 0.08, 0.45, 0.08))
        tris.append(v(landingPadStart, bot, 0.08, 0.45, 0.08))
        upload(encoder: enc, vertices: tris, uniforms: &u, type: .triangle)

        var lines: [Vertex2D] = []
        let pw = landingPadEnd - landingPadStart
        for i in 0...5 {
            let mx = landingPadStart + Float(i) * pw / 5.0
            lines.append(v(mx, top, 1.0, 1.0, 0.0))
            lines.append(v(mx, top + 8.0, 1.0, 1.0, 0.0))
        }
        upload(encoder: enc, vertices: lines, uniforms: &u, type: .line)

        drawWindFlag(enc: enc, u: &u, padTop: top)
        drawFloatingObjects(enc: enc, u: &u)
        drawShieldBlasters(enc: enc, u: &u)
        drawScorePopups(enc: enc, u: &u)
    }

    func drawShieldBlasters(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        guard !activeShields.isEmpty else { return }

        var lines: [Vertex2D] = []
        let segments = 56
        let baseR: Float = 0.45, baseG: Float = 0.85, baseB: Float = 1.0

        for shield in activeShields {
            let t = min(shield.elapsed / shield.duration, 1.0)
            let radius = currentShieldRadius(for: shield)
            // Alpha = 1 during growth (first half), then linearly fades.
            let alpha: Float = t < 0.5 ? 1.0 : max(1.0 - (t - 0.5) / 0.5, 0)
            if radius < 1 || alpha <= 0 { continue }

            // Concentric rings form a thick energy band — slight halo outside the
            // peak, dense core, and a softer inner glow trailing toward the centre.
            let rings: [(rScale: Float, aScale: Float)] = [
                (1.05, alpha * 0.35),
                (1.03, alpha * 0.65),
                (1.01, alpha * 0.90),
                (1.00, alpha),
                (0.99, alpha),
                (0.97, alpha * 0.95),
                (0.95, alpha * 0.80),
                (0.92, alpha * 0.55),
                (0.88, alpha * 0.30),
                (0.84, alpha * 0.15),
            ]

            for ring in rings {
                let r = radius * ring.rScale
                for i in 0..<segments {
                    let a0 = Float(i)     / Float(segments) * 2.0 * .pi
                    let a1 = Float(i + 1) / Float(segments) * 2.0 * .pi
                    let x0 = shield.x + cos(a0) * r
                    let y0 = shield.y + sin(a0) * r
                    let x1 = shield.x + cos(a1) * r
                    let y1 = shield.y + sin(a1) * r
                    lines.append(v(x0, y0, baseR, baseG, baseB, ring.aScale))
                    lines.append(v(x1, y1, baseR, baseG, baseB, ring.aScale))
                }
            }
        }

        if !lines.isEmpty {
            upload(encoder: enc, vertices: lines, uniforms: &u, type: .line)
        }
    }

    func drawScorePopups(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        guard !scorePopups.isEmpty else { return }
        let scale: Float = 1.6
        for p in scorePopups {
            let frac = max(p.life / p.maxLife, 0)
            // Fade by dimming toward black (drawText has no alpha channel).
            let r: Float = 1.0  * frac
            let g: Float = 0.95 * frac
            let b: Float = 0.30 * frac
            let textW = Float(p.text.count) * 7.0 * scale
            drawText(p.text, x: p.x - textW / 2.0, y: p.y, scale: scale,
                     r: r, g: g, b: b, enc: enc, u: &u)
        }
    }

    func drawFloatingObjects(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        guard !floatingObjects.isEmpty, let pipeline = texturePipeline else { return }

        enc.setRenderPipelineState(pipeline)

        for obj in floatingObjects where obj.alive {
            let hw = obj.width * 0.5
            let hh = obj.height * 0.5
            let cR = cos(obj.rotation), sR = sin(obj.rotation)
            func P(_ dx: Float, _ dy: Float) -> (Float, Float) {
                return (obj.x + dx * cR - dy * sR, obj.y + dx * sR + dy * cR)
            }
            let tl = P(-hw,  hh)   // local top-left  → texture uv (0, 0)
            let tr = P( hw,  hh)   // local top-right → texture uv (1, 0)
            let br = P( hw, -hh)   // local bot-right → texture uv (1, 1)
            let bl = P(-hw, -hh)   // local bot-left  → texture uv (0, 1)

            // Two triangles, vertex order matching drawLogo.
            var verts: [VertexUV] = [
                VertexUV(position: SIMD2<Float>(gx(bl.0), gy(bl.1)), texCoord: SIMD2<Float>(0, 1)),
                VertexUV(position: SIMD2<Float>(gx(br.0), gy(br.1)), texCoord: SIMD2<Float>(1, 1)),
                VertexUV(position: SIMD2<Float>(gx(tr.0), gy(tr.1)), texCoord: SIMD2<Float>(1, 0)),
                VertexUV(position: SIMD2<Float>(gx(bl.0), gy(bl.1)), texCoord: SIMD2<Float>(0, 1)),
                VertexUV(position: SIMD2<Float>(gx(tr.0), gy(tr.1)), texCoord: SIMD2<Float>(1, 0)),
                VertexUV(position: SIMD2<Float>(gx(tl.0), gy(tl.1)), texCoord: SIMD2<Float>(0, 0)),
            ]

            let byteSize = verts.count * MemoryLayout<VertexUV>.stride
            let totalBufferSize = maxVertices * MemoryLayout<Vertex2D>.stride
            guard vertexBufferOffset + byteSize <= totalBufferSize else { return }

            memcpy(vertexBuffer.contents() + vertexBufferOffset, &verts, byteSize)
            enc.setVertexBuffer(vertexBuffer, offset: vertexBufferOffset, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms2D>.stride, index: 1)
            enc.setFragmentTexture(obj.texture, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            vertexBufferOffset += byteSize
        }
    }

    func drawWindFlag(enc: MTLRenderCommandEncoder, u: inout Uniforms2D, padTop: Float) {
        guard windBase > 0 else { return }

        let poleX = landingPadEnd - 5
        let poleBase = padTop
        let poleHeight: Float = 28
        let poleTop = poleBase + poleHeight

        var lines: [Vertex2D] = []
        lines.append(v(poleX, poleBase, 0.85, 0.85, 0.9))
        lines.append(v(poleX, poleTop, 0.85, 0.85, 0.9))
        upload(encoder: enc, vertices: lines, uniforms: &u, type: .line)

        // Flag triangle — straight when wind is strong, drooping as it weakens, invisible at calm.
        let strength = min(abs(windForce) / 0.8, 1.0)
        guard strength > 0.05 else { return }

        let dir: Float = windForce >= 0 ? 1.0 : -1.0
        let flagLength: Float = 16
        let flagHeight: Float = 8
        let tipExtend = flagLength * (0.3 + 0.7 * strength)
        let droop = (1.0 - strength) * 14.0
        let tipX = poleX + dir * tipExtend
        let tipY = poleTop - flagHeight * 0.5 - droop

        var tris: [Vertex2D] = []
        let fr: Float = 0.95, fg: Float = 0.85, fb: Float = 0.30
        tris.append(v(poleX, poleTop, fr, fg, fb))
        tris.append(v(poleX, poleTop - flagHeight, fr, fg, fb))
        tris.append(v(tipX, tipY, fr, fg, fb))
        upload(encoder: enc, vertices: tris, uniforms: &u, type: .triangle)
    }

    // MARK: - Draw Lander

    func drawLander(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = landerX, cy = landerY

        var angle: Float = 0
        if gameState == .tippedOver {
            let elapsed = gameTime - stateChangeTime
            let progress = min(elapsed / 0.8, 1.0)
            angle = tipDirection * progress * Float.pi / 2.0
        }

        let cosA = cos(angle), sinA = sin(angle)
        func rot(_ dx: Float, _ dy: Float) -> (Float, Float) {
            return (cx + dx * cosA - dy * sinA, cy + dx * sinA + dy * cosA)
        }

        let bw = landerW / 2.0
        let bTop = landerH / 2.0
        let bBot = -landerH / 2.0

        let p0 = rot(-bw, bBot)
        let p1 = rot(bw, bBot)
        let p2 = rot(bw * 0.7, bTop)
        let p3 = rot(-bw * 0.7, bTop)

        var tris: [Vertex2D] = []
        let br: Float = 0.82, bg: Float = 0.82, bb: Float = 0.88
        let dr: Float = 0.55, dg: Float = 0.55, db: Float = 0.6

        tris.append(v(p0.0, p0.1, dr, dg, db))
        tris.append(v(p1.0, p1.1, dr, dg, db))
        tris.append(v(p2.0, p2.1, br, bg, bb))
        tris.append(v(p0.0, p0.1, dr, dg, db))
        tris.append(v(p2.0, p2.1, br, bg, bb))
        tris.append(v(p3.0, p3.1, br, bg, bb))

        let w0 = rot(-bw * 0.35, bTop * 0.15)
        let w1 = rot(bw * 0.35, bTop * 0.15)
        let w2 = rot(bw * 0.25, bTop * 0.7)
        let w3 = rot(-bw * 0.25, bTop * 0.7)

        tris.append(v(w0.0, w0.1, 0.85, 0.75, 0.15))
        tris.append(v(w1.0, w1.1, 0.85, 0.75, 0.15))
        tris.append(v(w2.0, w2.1, 1.0, 0.95, 0.35))
        tris.append(v(w0.0, w0.1, 0.85, 0.75, 0.15))
        tris.append(v(w2.0, w2.1, 1.0, 0.95, 0.35))
        tris.append(v(w3.0, w3.1, 1.0, 0.95, 0.35))

        let n0 = rot(-6, bBot)
        let n1 = rot(6, bBot)
        let n2 = rot(9, bBot - 8)
        let n3 = rot(-9, bBot - 8)
        tris.append(v(n0.0, n0.1, 0.5, 0.5, 0.55))
        tris.append(v(n1.0, n1.1, 0.5, 0.5, 0.55))
        tris.append(v(n2.0, n2.1, 0.35, 0.35, 0.4))
        tris.append(v(n0.0, n0.1, 0.5, 0.5, 0.55))
        tris.append(v(n2.0, n2.1, 0.35, 0.35, 0.4))
        tris.append(v(n3.0, n3.1, 0.35, 0.35, 0.4))

        upload(encoder: enc, vertices: tris, uniforms: &u, type: .triangle)

        var lines: [Vertex2D] = []
        let lc: (Float, Float, Float) = (0.7, 0.7, 0.75)

        let ll0 = rot(-bw + 2, bBot); let ll1 = rot(-legSpread / 2.0, bBot - legHeight)
        lines.append(v(ll0.0, ll0.1, lc.0, lc.1, lc.2))
        lines.append(v(ll1.0, ll1.1, lc.0, lc.1, lc.2))
        let lf0 = rot(-legSpread / 2.0 - 4, bBot - legHeight)
        let lf1 = rot(-legSpread / 2.0 + 4, bBot - legHeight)
        lines.append(v(lf0.0, lf0.1, lc.0, lc.1, lc.2))
        lines.append(v(lf1.0, lf1.1, lc.0, lc.1, lc.2))
        let ls0 = rot(-bw * 0.3, bBot + 5)
        lines.append(v(ls0.0, ls0.1, lc.0, lc.1, lc.2))
        lines.append(v(ll1.0, ll1.1, lc.0, lc.1, lc.2))

        let rl0 = rot(bw - 2, bBot); let rl1 = rot(legSpread / 2.0, bBot - legHeight)
        lines.append(v(rl0.0, rl0.1, lc.0, lc.1, lc.2))
        lines.append(v(rl1.0, rl1.1, lc.0, lc.1, lc.2))
        let rf0 = rot(legSpread / 2.0 - 4, bBot - legHeight)
        let rf1 = rot(legSpread / 2.0 + 4, bBot - legHeight)
        lines.append(v(rf0.0, rf0.1, lc.0, lc.1, lc.2))
        lines.append(v(rf1.0, rf1.1, lc.0, lc.1, lc.2))
        let rs0 = rot(bw * 0.3, bBot + 5)
        lines.append(v(rs0.0, rs0.1, lc.0, lc.1, lc.2))
        lines.append(v(rl1.0, rl1.1, lc.0, lc.1, lc.2))

        let lt0 = rot(-bw, 0); let lt1 = rot(-bw - 5, 3); let lt2 = rot(-bw - 5, -3)
        lines.append(v(lt0.0, lt0.1, 0.5, 0.5, 0.55))
        lines.append(v(lt1.0, lt1.1, 0.5, 0.5, 0.55))
        lines.append(v(lt0.0, lt0.1, 0.5, 0.5, 0.55))
        lines.append(v(lt2.0, lt2.1, 0.5, 0.5, 0.55))

        let rt0 = rot(bw, 0); let rt1 = rot(bw + 5, 3); let rt2 = rot(bw + 5, -3)
        lines.append(v(rt0.0, rt0.1, 0.5, 0.5, 0.55))
        lines.append(v(rt1.0, rt1.1, 0.5, 0.5, 0.55))
        lines.append(v(rt0.0, rt0.1, 0.5, 0.5, 0.55))
        lines.append(v(rt2.0, rt2.1, 0.5, 0.5, 0.55))

        upload(encoder: enc, vertices: lines, uniforms: &u, type: .line)

        if input.thrustMain && fuel > 0 && gameState == .playing {
            let flicker = Float.random(in: 0.6...1.0)
            let fLen = Float.random(in: 15...30)
            var flame: [Vertex2D] = []
            let f0 = rot(-7, bBot - 8)
            let f1 = rot(7, bBot - 8)
            let f2 = rot(0, bBot - 8 - fLen)
            flame.append(v(f0.0, f0.1, 1.0, 0.8 * flicker, 0.1, 0.9))
            flame.append(v(f1.0, f1.1, 1.0, 0.8 * flicker, 0.1, 0.9))
            flame.append(v(f2.0, f2.1, 1.0, 0.3 * flicker, 0.0, 0.0))
            upload(encoder: enc, vertices: flame, uniforms: &u, type: .triangle)
        }
    }

    // MARK: - Draw Particles

    func drawParticles(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        guard !particles.isEmpty else { return }
        var tris: [Vertex2D] = []
        let sz: Float = 2.5
        for p in particles {
            let a = p.life / p.maxLife
            tris.append(v(p.x - sz, p.y - sz, p.r, p.g, p.b, a))
            tris.append(v(p.x + sz, p.y - sz, p.r, p.g, p.b, a))
            tris.append(v(p.x + sz, p.y + sz, p.r, p.g, p.b, a))
            tris.append(v(p.x - sz, p.y - sz, p.r, p.g, p.b, a))
            tris.append(v(p.x + sz, p.y + sz, p.r, p.g, p.b, a))
            tris.append(v(p.x - sz, p.y + sz, p.r, p.g, p.b, a))
        }
        upload(encoder: enc, vertices: tris, uniforms: &u, type: .triangle)
    }

    // MARK: - Draw HUD

    func drawHUD(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let w = gameWidth
        let h = gameHeight
        let hudH: Float = 75.0
        let hudY = h - hudH
        let textScale: Float = 1.8

        // Background
        var bg: [Vertex2D] = []
        bg.append(v(0, hudY, 0, 0, 0, 0.65))
        bg.append(v(w, hudY, 0, 0, 0, 0.65))
        bg.append(v(w, h, 0, 0, 0, 0.65))
        bg.append(v(0, hudY, 0, 0, 0, 0.65))
        bg.append(v(w, h, 0, 0, 0, 0.65))
        bg.append(v(0, h, 0, 0, 0, 0.65))
        upload(encoder: enc, vertices: bg, uniforms: &u, type: .triangle)

        // Fuel bar
        let fbX: Float = 25.0, fbY = hudY + 14.0
        let fbW: Float = 150.0, fbH: Float = 20.0
        let ff = fuel / max(initialFuel, 1)

        var ol: [Vertex2D] = []
        ol.append(v(fbX, fbY, 0.6, 0.6, 0.6))
        ol.append(v(fbX + fbW, fbY, 0.6, 0.6, 0.6))
        ol.append(v(fbX + fbW, fbY, 0.6, 0.6, 0.6))
        ol.append(v(fbX + fbW, fbY + fbH, 0.6, 0.6, 0.6))
        ol.append(v(fbX + fbW, fbY + fbH, 0.6, 0.6, 0.6))
        ol.append(v(fbX, fbY + fbH, 0.6, 0.6, 0.6))
        ol.append(v(fbX, fbY + fbH, 0.6, 0.6, 0.6))
        ol.append(v(fbX, fbY, 0.6, 0.6, 0.6))
        upload(encoder: enc, vertices: ol, uniforms: &u, type: .line)

        let fillW = fbW * ff
        let fr: Float = ff < 0.25 ? 1.0 : 0.15
        let fg: Float = ff < 0.25 ? 0.15 : 0.8
        let fb: Float = 0.15
        if fillW > 2 {
            var fill: [Vertex2D] = []
            fill.append(v(fbX + 1, fbY + 1, fr, fg, fb))
            fill.append(v(fbX + fillW - 1, fbY + 1, fr, fg, fb))
            fill.append(v(fbX + fillW - 1, fbY + fbH - 1, fr, fg, fb))
            fill.append(v(fbX + 1, fbY + 1, fr, fg, fb))
            fill.append(v(fbX + fillW - 1, fbY + fbH - 1, fr, fg, fb))
            fill.append(v(fbX + 1, fbY + fbH - 1, fr, fg, fb))
            upload(encoder: enc, vertices: fill, uniforms: &u, type: .triangle)
        }

        drawText("FUEL", x: fbX, y: fbY + fbH + 5, scale: textScale,
                 r: 0.8, g: 0.8, b: 0.8, enc: enc, u: &u)

        let pctStr = String(format: "%.0f%%", ff * 100)
        drawText(pctStr, x: fbX + fbW + 8, y: fbY + 4, scale: 1.5,
                 r: fr, g: fg, b: fb, enc: enc, u: &u)

        // Speeds
        let vSpd = String(format: "V.SPD: %.1f M/S", -velocityY)
        let vSafe = abs(velocityY) <= maxLandingVSpeed
        drawText(vSpd, x: 230, y: fbY + fbH + 5, scale: textScale,
                 r: vSafe ? 0.4 : 1.0, g: vSafe ? 1.0 : 0.4, b: 0.4, enc: enc, u: &u)

        let hSpd = String(format: "H.SPD: %.1f M/S", velocityX)
        let hSafe = abs(velocityX) <= maxLandingHSpeed
        drawText(hSpd, x: 230, y: fbY + 4, scale: textScale,
                 r: hSafe ? 0.4 : 1.0, g: hSafe ? 1.0 : 0.4, b: 0.4, enc: enc, u: &u)

        // Altitude
        let alt = max(0, (landerY - landerH / 2.0 - legHeight - terrainHeightAt(x: landerX))) / pixelsPerMeter
        let altStr = String(format: "ALT: %.0f M", alt)
        drawText(altStr, x: 480, y: fbY + fbH + 5, scale: textScale,
                 r: 0.4, g: 0.75, b: 1.0, enc: enc, u: &u)

        // Pad direction
        let padCenter = (landingPadStart + landingPadEnd) / 2.0
        let padDir = padCenter > landerX ? "PAD >" : "< PAD"
        let padDist = abs(padCenter - landerX) / pixelsPerMeter
        let padStr = String(format: "%@ %.0fM", padDir, padDist)
        drawText(padStr, x: 480, y: fbY + 4, scale: textScale,
                 r: 0.4, g: 0.9, b: 0.4, enc: enc, u: &u)

        // Score and level
        let scoreStr = String(format: "SCORE: %d", totalScore)
        drawText(scoreStr, x: 660, y: fbY + fbH + 5, scale: textScale,
                 r: 1.0, g: 0.9, b: 0.2, enc: enc, u: &u)

        let levelStr = String(format: "LEVEL: %d", currentLevel)
        drawText(levelStr, x: 660, y: fbY + 4, scale: textScale,
                 r: 0.4, g: 0.75, b: 1.0, enc: enc, u: &u)

        // Lives — colored by how many remain
        let livesStr = String(format: "LIVES: %d", lives)
        let lr: Float = lives >= 3 ? 0.4 : (lives == 2 ? 1.0 : 1.0)
        let lg: Float = lives >= 3 ? 1.0 : (lives == 2 ? 1.0 : 0.4)
        let lb: Float = lives >= 3 ? 0.4 : (lives == 2 ? 0.4 : 0.4)
        drawText(livesStr, x: 850, y: fbY + fbH + 5, scale: textScale,
                 r: lr, g: lg, b: lb, enc: enc, u: &u)

        // Shield blasters — cyan, dimmer when empty.
        let shieldsStr = String(format: "SHIELD: %d", shieldsRemaining)
        let sr: Float = shieldsRemaining > 0 ? 0.4 : 0.35
        let sg: Float = shieldsRemaining > 0 ? 0.85 : 0.35
        let sb: Float = shieldsRemaining > 0 ? 1.0 : 0.4
        drawText(shieldsStr, x: 850, y: fbY + 4, scale: textScale,
                 r: sr, g: sg, b: sb, enc: enc, u: &u)

        // Wind indicator (level 2+) — sits in its own row at the bottom of the HUD bar
        if atmosphereDrag > 0 {
            let absWind = abs(windForce)
            let arrows: String
            if absWind < 0.1 {
                arrows = "---"
            } else {
                let count = min(Int(absWind / 0.25) + 1, 4)
                let arrow = windForce < 0 ? "<" : ">"
                arrows = String(repeating: arrow, count: count)
            }
            let wr: Float = absWind > 0.8 ? 1.0 : 0.4
            let wg: Float = absWind > 0.8 ? 0.5 : 0.85
            let wb: Float = absWind > 0.8 ? 0.2 : 1.0
            drawText("WIND: " + arrows, x: 480, y: hudY + 2, scale: textScale,
                     r: wr, g: wg, b: wb, enc: enc, u: &u)
        }
    }

    // MARK: - Logo Screen

    func drawLogo(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0

        // Draw logo texture if available
        if let tex = logoTexture, let pipeline = texturePipeline {
            let texW = Float(tex.width)
            let texH = Float(tex.height)
            let aspect = texW / texH

            // Scale logo to fill the screen (fit to screen, maintain aspect ratio)
            var logoW = gameWidth
            var logoH = logoW / aspect
            if logoH > gameHeight {
                logoH = gameHeight
                logoW = logoH * aspect
            }

            let logoX = cx - logoW / 2.0
            let logoY = (gameHeight - logoH) / 2.0

            // Build textured quad (two triangles)
            let x0 = gx(logoX), y0 = gy(logoY)
            let x1 = gx(logoX + logoW), y1 = gy(logoY + logoH)

            var verts: [VertexUV] = [
                VertexUV(position: SIMD2<Float>(x0, y0), texCoord: SIMD2<Float>(0, 1)),
                VertexUV(position: SIMD2<Float>(x1, y0), texCoord: SIMD2<Float>(1, 1)),
                VertexUV(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(1, 0)),
                VertexUV(position: SIMD2<Float>(x0, y0), texCoord: SIMD2<Float>(0, 1)),
                VertexUV(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(1, 0)),
                VertexUV(position: SIMD2<Float>(x0, y1), texCoord: SIMD2<Float>(0, 0)),
            ]

            let byteSize = verts.count * MemoryLayout<VertexUV>.stride
            let totalBufferSize = maxVertices * MemoryLayout<Vertex2D>.stride
            if vertexBufferOffset + byteSize <= totalBufferSize {
                memcpy(vertexBuffer.contents() + vertexBufferOffset, &verts, byteSize)
                enc.setRenderPipelineState(pipeline)
                enc.setVertexBuffer(vertexBuffer, offset: vertexBufferOffset, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms2D>.stride, index: 1)
                enc.setFragmentTexture(tex, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                vertexBufferOffset += byteSize
            }
        }

        // Press R - blinking
        if sin(gameTime * 3.0) > -0.4 {
            let startStr = isTouchDevice ? "TAP TO START" : "PRESS R TO START"
            let startScale: Float = 2.5
            let startW = Float(startStr.count) * 7.0 * startScale
            drawText(startStr, x: cx - startW / 2.0, y: gameHeight * 0.18, scale: startScale,
                     r: 0.9, g: 0.9, b: 0.9, enc: enc, u: &u)
        }

        // Instructions
        let instrScale: Float = 1.8
        let line1 = isTouchDevice ? "" : "ARROWS: STEER  SPACE: THRUST"
        let line1W = Float(line1.count) * 7.0 * instrScale
        drawText(line1, x: cx - line1W / 2.0, y: gameHeight * 0.10, scale: instrScale,
                 r: 0.5, g: 0.5, b: 0.5, enc: enc, u: &u)
    }

    // MARK: - Demo Overlay

    func drawDemoOverlay(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0

        // "DEMO" label
        let demoScale: Float = 3.0
        let demoStr = "DEMO"
        let demoW = Float(demoStr.count) * 7.0 * demoScale
        let pulse = (sin(gameTime * 2.5) + 1.0) / 2.0 * 0.3 + 0.7
        drawText(demoStr, x: cx - demoW / 2.0, y: gameHeight * 0.92, scale: demoScale,
                 r: 0.8 * pulse, g: 0.8 * pulse, b: 0.2 * pulse, enc: enc, u: &u)

        // Press R - blinking
        if sin(gameTime * 3.0) > -0.4 {
            let startStr = isTouchDevice ? "TAP TO START" : "PRESS R TO START"
            let startScale: Float = 2.0
            let startW = Float(startStr.count) * 7.0 * startScale
            drawText(startStr, x: cx - startW / 2.0, y: gameHeight * 0.86, scale: startScale,
                     r: 0.7, g: 0.7, b: 0.7, enc: enc, u: &u)
        }
    }

    // MARK: - Highscore Screen

    func drawHighscoreScreen(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0

        // Title
        let titleScale: Float = 4.0
        let titleStr = "HIGH SCORES"
        let titleW = Float(titleStr.count) * 7.0 * titleScale
        drawText(titleStr, x: cx - titleW / 2.0, y: gameHeight * 0.85,
                 scale: titleScale, r: 1.0, g: 0.9, b: 0.2, enc: enc, u: &u)

        // Column headers
        let hs: Float = 2.0
        let tableLeft: Float = 180
        let nameCol: Float = tableLeft + 70
        let scoreCol: Float = tableLeft + 420
        let lvlCol: Float = tableLeft + 600

        let headerY = gameHeight * 0.77
        drawText("RANK", x: tableLeft, y: headerY, scale: hs,
                 r: 0.3, g: 0.8, b: 0.9, enc: enc, u: &u)
        drawText("NAME", x: nameCol, y: headerY, scale: hs,
                 r: 0.3, g: 0.8, b: 0.9, enc: enc, u: &u)
        drawText("SCORE", x: scoreCol, y: headerY, scale: hs,
                 r: 0.3, g: 0.8, b: 0.9, enc: enc, u: &u)
        drawText("LVL", x: lvlCol, y: headerY, scale: hs,
                 r: 0.3, g: 0.8, b: 0.9, enc: enc, u: &u)

        // Entries
        let rowH: Float = 30.0
        let startY = headerY - 35.0
        let entries = HighscoreManager.shared.table.entries

        for i in 0..<min(entries.count, 10) {
            let y = startY - Float(i) * rowH
            let entry = entries[i]

            let (r, g, b): (Float, Float, Float)
            switch i {
            case 0: (r, g, b) = (1.0, 0.85, 0.2)    // gold
            case 1: (r, g, b) = (0.8, 0.8, 0.85)     // silver
            case 2: (r, g, b) = (0.8, 0.55, 0.2)     // bronze
            default: (r, g, b) = (0.7, 0.7, 0.7)
            }

            let rankStr = String(format: "%2d.", i + 1)
            drawText(rankStr, x: tableLeft, y: y, scale: hs, r: r, g: g, b: b, enc: enc, u: &u)
            drawText(entry.name, x: nameCol, y: y, scale: hs, r: r, g: g, b: b, enc: enc, u: &u)
            let scoreStr = String(format: "%d", entry.score)
            drawText(scoreStr, x: scoreCol, y: y, scale: hs, r: r, g: g, b: b, enc: enc, u: &u)
            let lvlStr = String(format: "%d", entry.level)
            drawText(lvlStr, x: lvlCol, y: y, scale: hs, r: r, g: g, b: b, enc: enc, u: &u)
        }

        // Press R - blinking
        if sin(gameTime * 3.0) > -0.4 {
            let promptStr = isTouchDevice ? "TAP TO START" : "PRESS R TO START"
            let promptScale: Float = 2.2
            let promptW = Float(promptStr.count) * 7.0 * promptScale
            drawText(promptStr, x: cx - promptW / 2.0, y: gameHeight * 0.10,
                     scale: promptScale, r: 0.9, g: 0.9, b: 0.9, enc: enc, u: &u)
        }
    }

    // MARK: - Name Entry Screen

    func drawNameEntryScreen(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0

        // All text is bunched into the top half of the playfield so the iOS keyboard
        // (which covers roughly the bottom 55% of the screen in landscape) does not
        // hide the input field or the prompts.
        let t1 = "NEW HIGH SCORE!"
        let t1s: Float = 3.5
        let t1w = Float(t1.count) * 7.0 * t1s
        drawText(t1, x: cx - t1w / 2.0, y: gameHeight * 0.90, scale: t1s,
                 r: 1.0, g: 0.9, b: 0.2, enc: enc, u: &u)

        let scoreStr = "YOUR SCORE: \(totalScore)"
        let ss: Float = 2.5
        let sw = Float(scoreStr.count) * 7.0 * ss
        drawText(scoreStr, x: cx - sw / 2.0, y: gameHeight * 0.82, scale: ss,
                 r: 0.2, g: 1.0, b: 0.2, enc: enc, u: &u)

        let prompt = "ENTER YOUR NAME:"
        let ps: Float = 2.2
        let pw = Float(prompt.count) * 7.0 * ps
        drawText(prompt, x: cx - pw / 2.0, y: gameHeight * 0.74, scale: ps,
                 r: 0.8, g: 0.8, b: 0.8, enc: enc, u: &u)

        // Name field
        let nameScale: Float = 3.5
        let maxChars = 10
        let fieldW = Float(maxChars) * 7.0 * nameScale
        let fieldX = cx - fieldW / 2.0
        let fieldY = gameHeight * 0.66

        drawText(enteredName, x: fieldX, y: fieldY, scale: nameScale,
                 r: 0.2, g: 1.0, b: 0.4, enc: enc, u: &u)

        // Blinking cursor
        if sin(nameCursorBlink * 4.0) > 0 && enteredName.count < maxChars {
            let cursorX = fieldX + Float(enteredName.count) * 7.0 * nameScale
            var cursorVerts: [Vertex2D] = []
            cursorVerts.append(v(cursorX, fieldY - 2, 0.2, 1.0, 0.4))
            cursorVerts.append(v(cursorX + 5.0 * nameScale, fieldY - 2, 0.2, 1.0, 0.4))
            upload(encoder: enc, vertices: cursorVerts, uniforms: &u, type: .line)
        }

        let instr = isTouchDevice ? "TAP DONE TO CONFIRM" : "PRESS RETURN TO CONFIRM"
        let is2: Float = 1.8
        let iw = Float(instr.count) * 7.0 * is2
        drawText(instr, x: cx - iw / 2.0, y: gameHeight * 0.58, scale: is2,
                 r: 0.5, g: 0.5, b: 0.5, enc: enc, u: &u)
    }

    // MARK: - Game Messages

    func drawLandedMessage(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0
        let cy = gameHeight / 2.0

        drawText("LANDED SAFELY!", x: cx - 130, y: cy + 40, scale: 3.5,
                 r: 0.15, g: 1.0, b: 0.15, enc: enc, u: &u)

        let scorePreview = calculateLevelScore()
        let scoreStr = String(format: "+%d POINTS", scorePreview)
        let sw = Float(scoreStr.count) * 7.0 * 2.2
        drawText(scoreStr, x: cx - sw / 2.0, y: cy, scale: 2.2,
                 r: 1.0, g: 0.9, b: 0.2, enc: enc, u: &u)
    }

    func drawLevelTransition(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0
        let cy = gameHeight / 2.0

        let lvlStr = String(format: "LEVEL %d COMPLETE!", currentLevel)
        let ls: Float = 3.5
        let lw = Float(lvlStr.count) * 7.0 * ls
        drawText(lvlStr, x: cx - lw / 2.0, y: cy + 50, scale: ls,
                 r: 0.15, g: 1.0, b: 0.15, enc: enc, u: &u)

        let lsStr = String(format: "LEVEL SCORE: %d", lastLevelScore)
        let lss: Float = 2.2
        let lsw = Float(lsStr.count) * 7.0 * lss
        drawText(lsStr, x: cx - lsw / 2.0, y: cy + 10, scale: lss,
                 r: 0.8, g: 0.8, b: 0.8, enc: enc, u: &u)

        let tsStr = String(format: "TOTAL SCORE: %d", totalScore)
        let tss: Float = 2.5
        let tsw = Float(tsStr.count) * 7.0 * tss
        drawText(tsStr, x: cx - tsw / 2.0, y: cy - 25, scale: tss,
                 r: 1.0, g: 0.9, b: 0.2, enc: enc, u: &u)

        // Upcoming conditions warning
        let nextLevel = currentLevel + 1
        let condStr: String
        switch nextLevel {
        case 2: condStr = "ENTERING ATMOSPHERE..."
        case 3: condStr = "WIND PICKING UP..."
        default: condStr = "CONDITIONS WORSENING..."
        }
        let cs: Float = 2.0
        let csw = Float(condStr.count) * 7.0 * cs
        drawText(condStr, x: cx - csw / 2.0, y: cy - 65, scale: cs,
                 r: 0.9, g: 0.5, b: 0.2, enc: enc, u: &u)
    }

    func drawCrashedMessage(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0
        let cy = gameHeight / 2.0

        drawText("CRASHED!", x: cx - 80, y: cy + 40, scale: 3.5,
                 r: 1.0, g: 0.15, b: 0.15, enc: enc, u: &u)

        drawLivesOverlay(at: cy, enc: enc, u: &u)
    }

    func drawTippedOverMessage(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0
        let cy = gameHeight / 2.0

        drawText("TIPPED OVER!", x: cx - 110, y: cy + 40, scale: 3.5,
                 r: 1.0, g: 0.6, b: 0.15, enc: enc, u: &u)

        let sub = "TOO MUCH HORIZONTAL SPEED"
        let ss: Float = 2.0
        let sw = Float(sub.count) * 7.0 * ss
        drawText(sub, x: cx - sw / 2.0, y: cy + 5, scale: ss,
                 r: 0.8, g: 0.6, b: 0.3, enc: enc, u: &u)

        drawLivesOverlay(at: cy - 40, enc: enc, u: &u)
    }

    /// Shared lives + retry prompt drawn beneath the crash/tip messages.
    private func drawLivesOverlay(at baseY: Float, enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0
        let livesStr = lives > 0
            ? String(format: "LIVES REMAINING: %d", lives)
            : "NO LIVES LEFT"
        let ls: Float = 2.2
        let lw = Float(livesStr.count) * 7.0 * ls
        let lr: Float = lives > 0 ? 1.0 : 0.6
        let lg: Float = lives > 0 ? 0.85 : 0.15
        let lb: Float = lives > 0 ? 0.25 : 0.15
        drawText(livesStr, x: cx - lw / 2.0, y: baseY - 50, scale: ls,
                 r: lr, g: lg, b: lb, enc: enc, u: &u)

        if lives > 0 && gameTime - stateChangeTime >= 0.6 {
            let prompt = isTouchDevice ? "TAP TO CONTINUE" : "PRESS ANY KEY TO CONTINUE"
            let ps: Float = 1.8
            let pw = Float(prompt.count) * 7.0 * ps
            // Soft pulse so it reads as interactive.
            let pulse = 0.7 + 0.3 * sin(gameTime * 4.0)
            drawText(prompt, x: cx - pw / 2.0, y: baseY - 95, scale: ps,
                     r: 0.9 * pulse, g: 0.9 * pulse, b: 0.95 * pulse, enc: enc, u: &u)
        }
    }

    func drawGameOverMessage(enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        let cx = gameWidth / 2.0
        let cy = gameHeight / 2.0

        let go = "GAME OVER"
        let gs: Float = 4.0
        let gw = Float(go.count) * 7.0 * gs
        drawText(go, x: cx - gw / 2.0, y: cy + 50, scale: gs,
                 r: 1.0, g: 0.15, b: 0.15, enc: enc, u: &u)

        let ts = String(format: "TOTAL SCORE: %d", totalScore)
        let tss: Float = 2.5
        let tsw = Float(ts.count) * 7.0 * tss
        drawText(ts, x: cx - tsw / 2.0, y: cy + 5, scale: tss,
                 r: 0.8, g: 0.8, b: 0.8, enc: enc, u: &u)

        let lr = String(format: "LEVEL REACHED: %d", currentLevel)
        let lrs: Float = 2.0
        let lrw = Float(lr.count) * 7.0 * lrs
        drawText(lr, x: cx - lrw / 2.0, y: cy - 25, scale: lrs,
                 r: 0.6, g: 0.6, b: 0.6, enc: enc, u: &u)
    }

    // MARK: - Vector Text

    func drawText(_ text: String, x: Float, y: Float, scale: Float,
                  r: Float, g: Float, b: Float,
                  enc: MTLRenderCommandEncoder, u: inout Uniforms2D) {
        var lines: [Vertex2D] = []
        var cx = x
        let cw: Float = 7.0 * scale

        for char in text.uppercased() {
            for seg in charSegs(char) {
                lines.append(v(cx + seg.0 * scale, y + seg.1 * scale, r, g, b))
                lines.append(v(cx + seg.2 * scale, y + seg.3 * scale, r, g, b))
            }
            cx += cw
        }
        if !lines.isEmpty {
            upload(encoder: enc, vertices: lines, uniforms: &u, type: .line)
        }
    }

    func charSegs(_ c: Character) -> [(Float, Float, Float, Float)] {
        let w: Float = 5, h: Float = 9, m = h / 2
        switch c {
        case "A": return [(0,0,w/2,h),(w/2,h,w,0),(w*0.2,m*0.8,w*0.8,m*0.8)]
        case "B": return [(0,0,0,h),(0,h,w*0.8,h),(w*0.8,h,w,h-1),(w,h-1,w,m+1),(w,m+1,w*0.8,m),(0,m,w*0.8,m),(w*0.8,m,w,m-1),(w,m-1,w,1),(w,1,w*0.8,0),(w*0.8,0,0,0)]
        case "C": return [(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,1),(0,1,1,0),(1,0,w-1,0),(w-1,0,w,1)]
        case "D": return [(0,0,0,h),(0,h,w-1,h),(w-1,h,w,h-2),(w,h-2,w,2),(w,2,w-1,0),(w-1,0,0,0)]
        case "E": return [(w,0,0,0),(0,0,0,h),(0,h,w,h),(0,m,w*0.7,m)]
        case "F": return [(0,0,0,h),(0,h,w,h),(0,m,w*0.7,m)]
        case "G": return [(w,h-1,1,h),(1,h,0,h-1),(0,h-1,0,1),(0,1,1,0),(1,0,w,0),(w,0,w,m),(w,m,w/2,m)]
        case "H": return [(0,0,0,h),(w,0,w,h),(0,m,w,m)]
        case "I": return [(w*0.2,0,w*0.8,0),(w/2,0,w/2,h),(w*0.2,h,w*0.8,h)]
        case "J": return [(0,1,1,0),(1,0,w-1,0),(w-1,0,w,1),(w,1,w,h),(w*0.3,h,w,h)]
        case "K": return [(0,0,0,h),(w,h,0,m),(0,m,w,0)]
        case "L": return [(0,h,0,0),(0,0,w,0)]
        case "M": return [(0,0,0,h),(0,h,w/2,m),(w/2,m,w,h),(w,h,w,0)]
        case "N": return [(0,0,0,h),(0,h,w,0),(w,0,w,h)]
        case "O": return [(1,0,w-1,0),(w-1,0,w,1),(w,1,w,h-1),(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,1),(0,1,1,0)]
        case "P": return [(0,0,0,h),(0,h,w,h),(w,h,w,m),(w,m,0,m)]
        case "Q": return [(1,0,w-1,0),(w-1,0,w,1),(w,1,w,h-1),(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,1),(0,1,1,0),(w*0.6,m*0.6,w+1,-1)]
        case "R": return [(0,0,0,h),(0,h,w,h),(w,h,w,m),(w,m,0,m),(w*0.4,m,w,0)]
        case "S": return [(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,m+1),(0,m+1,1,m),(1,m,w-1,m),(w-1,m,w,m-1),(w,m-1,w,1),(w,1,w-1,0),(w-1,0,1,0),(1,0,0,1)]
        case "T": return [(0,h,w,h),(w/2,0,w/2,h)]
        case "U": return [(0,h,0,1),(0,1,1,0),(1,0,w-1,0),(w-1,0,w,1),(w,1,w,h)]
        case "V": return [(0,h,w/2,0),(w/2,0,w,h)]
        case "W": return [(0,h,w*0.25,0),(w*0.25,0,w/2,m),(w/2,m,w*0.75,0),(w*0.75,0,w,h)]
        case "X": return [(0,0,w,h),(w,0,0,h)]
        case "Y": return [(0,h,w/2,m),(w,h,w/2,m),(w/2,m,w/2,0)]
        case "Z": return [(0,h,w,h),(w,h,0,0),(0,0,w,0)]
        case "0": return [(1,0,w-1,0),(w-1,0,w,1),(w,1,w,h-1),(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,1),(0,1,1,0),(0,0,w,h)]
        case "1": return [(w/2-1,h,w/2,h),(w/2,0,w/2,h),(w*0.2,0,w*0.8,0)]
        case "2": return [(0,h-1,1,h),(1,h,w-1,h),(w-1,h,w,h-1),(w,h-1,w,m),(w,m,0,0),(0,0,w,0)]
        case "3": return [(0,h-1,1,h),(1,h,w-1,h),(w-1,h,w,h-1),(w,h-1,w,m+1),(w,m+1,w/2,m),(w/2,m,w,m-1),(w,m-1,w,1),(w,1,w-1,0),(w-1,0,1,0),(1,0,0,1)]
        case "4": return [(0,h,0,m),(0,m,w,m),(w,h,w,0)]
        case "5": return [(w,h,0,h),(0,h,0,m),(0,m,w-1,m),(w-1,m,w,m-1),(w,m-1,w,1),(w,1,w-1,0),(w-1,0,0,0)]
        case "6": return [(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,1),(0,1,1,0),(1,0,w-1,0),(w-1,0,w,1),(w,1,w,m-1),(w,m-1,w-1,m),(w-1,m,0,m)]
        case "7": return [(0,h,w,h),(w,h,w/2,0)]
        case "8": return [(1,m,0,m+1),(0,m+1,0,h-1),(0,h-1,1,h),(1,h,w-1,h),(w-1,h,w,h-1),(w,h-1,w,m+1),(w,m+1,w-1,m),(w-1,m,w,m-1),(w,m-1,w,1),(w,1,w-1,0),(w-1,0,1,0),(1,0,0,1),(0,1,0,m-1),(0,m-1,1,m),(1,m,w-1,m)]
        case "9": return [(0,1,1,0),(1,0,w-1,0),(w-1,0,w,1),(w,1,w,h-1),(w,h-1,w-1,h),(w-1,h,1,h),(1,h,0,h-1),(0,h-1,0,m+1),(0,m+1,1,m),(1,m,w,m)]
        case ".": return [(w/2-0.5,0,w/2+0.5,0),(w/2+0.5,0,w/2+0.5,1),(w/2+0.5,1,w/2-0.5,1),(w/2-0.5,1,w/2-0.5,0)]
        case ":": return [(w/2-0.5,h*0.3,w/2+0.5,h*0.3),(w/2-0.5,h*0.7,w/2+0.5,h*0.7)]
        case "-": return [(1,m,w-1,m)]
        case "/": return [(0,0,w,h)]
        case "%": return [(0,0,w,h),(0.5,h,0.5,h-2),(1.5,h,1.5,h-2),(0.5,h,1.5,h),(0.5,h-2,1.5,h-2),(w-1.5,2,w-1.5,0),(w-0.5,2,w-0.5,0),(w-1.5,2,w-0.5,2),(w-1.5,0,w-0.5,0)]
        case ">": return [(0,h,w,m),(w,m,0,0)]
        case "<": return [(w,h,0,m),(0,m,w,0)]
        case "+": return [(w/2,1,w/2,h-1),(1,m,w-1,m)]
        case " ": return []
        case "!": return [(w/2,h,w/2,m*0.6),(w/2,0.5,w/2,0)]
        default: return [(0,0,w,0),(w,0,w,h),(w,h,0,h),(0,h,0,0)]
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = SIMD2<Float>(Float(size.width), Float(size.height))
        let aspect = Float(size.width) / Float(size.height)
        gameHeight = gameWidth / aspect

        if !initialSetupDone {
            initialSetupDone = true
            generateStars()
            generateTerrain()
            gameState = .logo
            stateChangeTime = 0
            gameTime = 0
            onStateChange?(.logo)
        }
    }
}
