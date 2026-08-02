//
//  GameViewController.swift
//  LunarLander
//
//  Handles keyboard input and sets up the Metal view
//

import Cocoa
import MetalKit
import AVFoundation

class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    var keyDownMonitor: Any?
    var keyUpMonitor: Any?
    var flagsChangedMonitor: Any?
    var controlKeyHeld: Bool = false

    // Music playback
    var musicPlayer: AVAudioPlayer?

    // Sound effects
    var enginePlayer: AVAudioPlayer?
    var windPlayer: AVAudioPlayer?
    var crashPlayer: AVAudioPlayer?
    var successPlayer: AVAudioPlayer?
    var blurpPlayer: AVAudioPlayer?
    var shieldPlayer: AVAudioPlayer?
    var currentWindFile: String = ""
    var windUpdateTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer
        self.mtkView = mtkView

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer

        // Setup audio
        setupMusic()
        setupSoundEffects()

        // State change callback for music and sound control
        renderer.onStateChange = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .logo, .highscores:
                self.startMusic()
                self.stopAllGameSounds()
            case .demo:
                self.startMusic()
                self.startWindSoundIfNeeded()
            case .playing:
                if !GameConfig.gameplayMusicEnabled {
                    self.pauseMusic()
                }
                self.startWindSoundIfNeeded()
            case .crashed, .tippedOver:
                self.stopAllGameSounds()
                if GameConfig.soundEffectsEnabled {
                    self.crashPlayer?.currentTime = 0
                    self.crashPlayer?.play()
                }
            case .landed:
                self.stopAllGameSounds()
                if GameConfig.soundEffectsEnabled {
                    self.successPlayer?.currentTime = 0
                    self.successPlayer?.play()
                }
            default:
                break
            }
        }

        renderer.onFuelPickup = { [weak self] in
            guard let self = self, GameConfig.soundEffectsEnabled else { return }
            self.successPlayer?.currentTime = 0
            self.successPlayer?.play()
        }

        renderer.onLightPickup = { [weak self] in
            guard let self = self, GameConfig.soundEffectsEnabled else { return }
            self.blurpPlayer?.currentTime = 0
            self.blurpPlayer?.play()
        }

        renderer.onHeavyDestroyed = { [weak self] in
            guard let self = self, GameConfig.soundEffectsEnabled else { return }
            self.crashPlayer?.currentTime = 0
            self.crashPlayer?.play()
        }

        renderer.onShieldDeployed = { [weak self] in
            guard let self = self, GameConfig.soundEffectsEnabled else { return }
            self.shieldPlayer?.currentTime = 0
            self.shieldPlayer?.play()
        }

        // Use local event monitors for reliable keyboard handling
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let renderer = self.renderer else { return event }

            switch renderer.gameState {
            case .enteringName:
                // Handle character input for name entry
                if !event.isARepeat {
                    switch event.keyCode {
                    case 36: // Return
                        renderer.confirmName()
                    case 51: // Backspace
                        renderer.deleteNameCharacter()
                    default:
                        if let chars = event.characters?.uppercased() {
                            for c in chars {
                                if c.isLetter || c == " " {
                                    renderer.appendNameCharacter(c)
                                }
                            }
                        }
                    }
                }
                // Consume all keys during name entry
                return nil

            case .playing:
                if !event.isARepeat {
                    self.handleKey(event.keyCode, pressed: true)
                    self.updateEngineSound()
                }
                // Consume game keys to prevent system beep
                switch event.keyCode {
                case 49, 123, 124, 125, 126:
                    return nil
                default:
                    return event
                }

            case .logo, .highscores, .demo:
                if !event.isARepeat {
                    if event.keyCode == 15 { // R key
                        renderer.startNewGame()
                        if !GameConfig.gameplayMusicEnabled {
                            self.pauseMusic()
                        }
                        return nil
                    }
                    // Number keys 1-9: jump to level (cheat/debug)
                    if GameConfig.cheatLevelSelectEnabled,
                       let chars = event.characters, let digit = chars.first,
                       let level = digit.wholeNumberValue, level >= 1 && level <= 9 {
                        renderer.startGameAtLevel(level)
                        if !GameConfig.gameplayMusicEnabled {
                            self.pauseMusic()
                        }
                        return nil
                    }
                }
                return event

            case .crashed, .tippedOver:
                // Any key restarts the current level — small cooldown prevents
                // accidental skip if the player was holding a thrust key at the
                // moment of impact.
                if !event.isARepeat
                    && renderer.lives > 0
                    && renderer.gameTime - renderer.stateChangeTime >= 0.6 {
                    renderer.retryCurrentLevel()
                    if !GameConfig.gameplayMusicEnabled {
                        self.pauseMusic()
                    }
                }
                return nil

            default:
                // Other states use auto-transitions, no input needed
                return event
            }
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self = self, let renderer = self.renderer else { return event }
            if renderer.gameState == .playing {
                self.handleKey(event.keyCode, pressed: false)
                self.updateEngineSound()
            }
            return event
        }

        // Left-Control fires the shield blaster. flagsChanged events fire on both
        // press and release for modifier keys; we only act on the down transition.
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self, let renderer = self.renderer else { return event }
            // keyCode 59 = Left Control. (Right Control is 62; ignore.)
            guard event.keyCode == 59 else { return event }
            let isDown = event.modifierFlags.contains(.control)
            if isDown && !self.controlKeyHeld {
                self.controlKeyHeld = true
                if renderer.gameState == .playing {
                    renderer.deployShieldBlaster()
                }
            } else if !isDown {
                self.controlKeyHeld = false
            }
            return event
        }
    }

    // MARK: - Music

    func setupMusic() {
        guard let url = Bundle.main.url(forResource: "Lunar Descent Loop", withExtension: "mp3") else {
            print("Music file not found in bundle")
            return
        }
        do {
            musicPlayer = try AVAudioPlayer(contentsOf: url)
            musicPlayer?.numberOfLoops = -1  // Loop forever
            musicPlayer?.volume = 0.6
            musicPlayer?.prepareToPlay()
            startMusic()
        } catch {
            print("Failed to load music: \(error)")
        }
    }

    func startMusic() {
        guard GameConfig.attractMusicEnabled else { return }
        if musicPlayer?.isPlaying == false {
            musicPlayer?.play()
        }
    }

    func pauseMusic() {
        musicPlayer?.pause()
    }

    // MARK: - Sound Effects

    func setupSoundEffects() {
        guard GameConfig.soundEffectsEnabled else { return }

        // Load engine sound
        if let url = Bundle.main.url(forResource: "navigation_rocket_engine", withExtension: "wav") {
            enginePlayer = try? AVAudioPlayer(contentsOf: url)
            enginePlayer?.numberOfLoops = -1
            enginePlayer?.volume = 0.4
            enginePlayer?.prepareToPlay()
        }

        // Load crash sound
        if let url = Bundle.main.url(forResource: "crash", withExtension: "mp3") {
            crashPlayer = try? AVAudioPlayer(contentsOf: url)
            crashPlayer?.volume = 0.6
            crashPlayer?.prepareToPlay()
        }

        // Load success sound
        if let url = Bundle.main.url(forResource: "succes", withExtension: "mp3") {
            successPlayer = try? AVAudioPlayer(contentsOf: url)
            successPlayer?.volume = 0.6
            successPlayer?.prepareToPlay()
        }

        // Load blurp sound (light-object pickup)
        if let url = Bundle.main.url(forResource: "blurp", withExtension: "mp3") {
            blurpPlayer = try? AVAudioPlayer(contentsOf: url)
            blurpPlayer?.volume = 0.5
            blurpPlayer?.prepareToPlay()
        }

        // Load shield-deploy sound
        if let url = Bundle.main.url(forResource: "Shield", withExtension: "mp3") {
            shieldPlayer = try? AVAudioPlayer(contentsOf: url)
            shieldPlayer?.volume = 0.6
            shieldPlayer?.prepareToPlay()
        }

        // Periodic timer for wind sound and engine sound (catches demo mode + fuel depletion)
        windUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateWindSound()
            self?.updateEngineSound()
        }
    }

    func updateEngineSound() {
        guard GameConfig.soundEffectsEnabled, let renderer = renderer else { return }
        let anyThrust = renderer.input.thrustMain || renderer.input.thrustLeft || renderer.input.thrustRight
        let shouldPlay = anyThrust && renderer.fuel > 0
            && (renderer.gameState == .playing || renderer.gameState == .demo)

        if shouldPlay {
            if enginePlayer?.isPlaying == false {
                enginePlayer?.play()
            }
        } else {
            if enginePlayer?.isPlaying == true {
                enginePlayer?.stop()
                enginePlayer?.currentTime = 0
            }
        }
    }

    func startWindSoundIfNeeded() {
        guard GameConfig.soundEffectsEnabled, let renderer = renderer else { return }
        if renderer.atmosphereDrag > 0 {
            updateWindSound()
        }
    }

    func updateWindSound() {
        guard GameConfig.soundEffectsEnabled, let renderer = renderer else { return }

        let isGameplay = renderer.gameState == .playing || renderer.gameState == .demo
        guard isGameplay && renderer.atmosphereDrag > 0 else {
            stopWindSound()
            return
        }

        let absWind = abs(renderer.windForce)
        let targetFile: String
        if absWind > 0.7 {
            targetFile = "wind_03_high"
        } else if absWind > 0.35 {
            targetFile = "wind_02_gusyt"
        } else {
            targetFile = "wind_01_low"
        }

        // Switch wind file if needed
        if targetFile != currentWindFile {
            stopWindSound()
            if let url = Bundle.main.url(forResource: targetFile, withExtension: "mp3") {
                windPlayer = try? AVAudioPlayer(contentsOf: url)
                windPlayer?.numberOfLoops = -1
                windPlayer?.volume = 0.0
                windPlayer?.prepareToPlay()
                windPlayer?.play()
                currentWindFile = targetFile
            }
        }

        // Scale volume with wind strength (0.15 to 0.7)
        let volume = min(0.7, max(0.15, absWind * 0.7))
        windPlayer?.volume = volume
    }

    func stopWindSound() {
        windPlayer?.stop()
        windPlayer = nil
        currentWindFile = ""
    }

    func stopAllGameSounds() {
        enginePlayer?.stop()
        enginePlayer?.currentTime = 0
        stopWindSound()
    }

    deinit {
        windUpdateTimer?.invalidate()
        if let monitor = keyDownMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = keyUpMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = flagsChangedMonitor { NSEvent.removeMonitor(monitor) }
    }

    override var acceptsFirstResponder: Bool { return true }

    override func becomeFirstResponder() -> Bool { return true }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(self)
    }

    private func handleKey(_ keyCode: UInt16, pressed: Bool) {
        guard renderer != nil else { return }
        switch keyCode {
        case 49: // Space bar
            renderer.input.thrustMain = pressed
        case 123: // Left arrow
            renderer.input.thrustLeft = pressed
        case 124: // Right arrow
            renderer.input.thrustRight = pressed
        default:
            break
        }
    }
}
