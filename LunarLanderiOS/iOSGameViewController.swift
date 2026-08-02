//
//  iOSGameViewController.swift
//  LunarLanderiOS
//
//  UIViewController with MTKView + on-screen touch controls for iOS
//

import UIKit
import MetalKit
import AVFoundation

class iOSGameViewController: UIViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

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

    // Touch control buttons
    var thrustButton: UIButton!
    var leftButton: UIButton!
    var rightButton: UIButton!
    var shieldButton: UIButton!

    // Name entry
    var nameTextField: UITextField?
    var nameEntryContainer: UIView?

    // MARK: - Lifecycle

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        // Setup Metal view
        mtkView = MTKView(frame: view.bounds)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        mtkView.device = device
        view.addSubview(mtkView)

        // Setup renderer
        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            fatalError("Renderer cannot be initialized")
        }
        renderer = newRenderer
        renderer.isTouchDevice = true
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer

        // Configure audio session for iOS
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }

        // Setup audio
        setupMusic()
        setupSoundEffects()

        // State change callback for music, sound, and UI control
        renderer.onStateChange = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .logo, .highscores:
                    self.startMusic()
                    self.stopAllGameSounds()
                    self.showControlButtons(false)
                    self.hideNameEntry()
                case .demo:
                    self.startMusic()
                    self.startWindSoundIfNeeded()
                    self.showControlButtons(false)
                case .playing:
                    if !GameConfig.gameplayMusicEnabled {
                        self.pauseMusic()
                    }
                    self.startWindSoundIfNeeded()
                    self.showControlButtons(true)
                    self.hideNameEntry()
                case .crashed, .tippedOver:
                    self.stopAllGameSounds()
                    self.showControlButtons(false)
                    if GameConfig.soundEffectsEnabled {
                        self.crashPlayer?.currentTime = 0
                        self.crashPlayer?.play()
                    }
                case .landed:
                    self.stopAllGameSounds()
                    self.showControlButtons(false)
                    if GameConfig.soundEffectsEnabled {
                        self.successPlayer?.currentTime = 0
                        self.successPlayer?.play()
                    }
                case .enteringName:
                    self.showControlButtons(false)
                    self.showNameEntry()
                default:
                    break
                }
            }
        }

        renderer.onFuelPickup = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard GameConfig.soundEffectsEnabled else { return }
                self.successPlayer?.currentTime = 0
                self.successPlayer?.play()
            }
        }

        renderer.onLightPickup = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard GameConfig.soundEffectsEnabled else { return }
                self.blurpPlayer?.currentTime = 0
                self.blurpPlayer?.play()
            }
        }

        renderer.onHeavyDestroyed = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard GameConfig.soundEffectsEnabled else { return }
                self.crashPlayer?.currentTime = 0
                self.crashPlayer?.play()
            }
        }

        renderer.onShieldDeployed = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard GameConfig.soundEffectsEnabled else { return }
                self.shieldPlayer?.currentTime = 0
                self.shieldPlayer?.play()
            }
        }

        // Setup touch controls
        setupControlButtons()

        // Add tap gesture for attract screens
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleScreenTap))
        tapGesture.cancelsTouchesInView = false
        mtkView.addGestureRecognizer(tapGesture)
    }

    // MARK: - Tap to Start

    @objc func handleScreenTap(_ gesture: UITapGestureRecognizer) {
        guard let renderer = renderer else { return }
        switch renderer.gameState {
        case .logo, .highscores, .demo:
            renderer.startNewGame()
            if !GameConfig.gameplayMusicEnabled {
                pauseMusic()
            }
        case .crashed, .tippedOver:
            if renderer.lives > 0
                && renderer.gameTime - renderer.stateChangeTime >= 0.6 {
                renderer.retryCurrentLevel()
                if !GameConfig.gameplayMusicEnabled {
                    pauseMusic()
                }
            }
        default:
            break
        }
    }

    // MARK: - Control Buttons

    func setupControlButtons() {
        let buttonSize: CGFloat = 90
        let thrustSize: CGFloat = 144
        let margin: CGFloat = 30
        let bottomMargin: CGFloat = 40

        // Main thrust button (left side, large)
        thrustButton = makeThrustButton(title: "THRUST", color: .systemOrange)
        view.addSubview(thrustButton)
        thrustButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            thrustButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: margin),
            thrustButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -bottomMargin),
            thrustButton.widthAnchor.constraint(equalToConstant: thrustSize),
            thrustButton.heightAnchor.constraint(equalToConstant: thrustSize),
        ])

        // Right thruster button (right side, bottom)
        rightButton = makeThrustButton(title: "▶", color: .systemBlue)
        view.addSubview(rightButton)
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rightButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -margin),
            rightButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -bottomMargin),
            rightButton.widthAnchor.constraint(equalToConstant: buttonSize),
            rightButton.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        // Left thruster button (right side, above right button)
        leftButton = makeThrustButton(title: "◀", color: .systemBlue)
        view.addSubview(leftButton)
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftButton.trailingAnchor.constraint(equalTo: rightButton.leadingAnchor, constant: -15),
            leftButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -bottomMargin),
            leftButton.widthAnchor.constraint(equalToConstant: buttonSize),
            leftButton.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        // Shield blaster (left side, above the thrust button)
        shieldButton = makeThrustButton(title: "SHIELD", color: .systemTeal)
        view.addSubview(shieldButton)
        shieldButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            shieldButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: margin),
            shieldButton.bottomAnchor.constraint(equalTo: thrustButton.topAnchor, constant: -15),
            shieldButton.widthAnchor.constraint(equalToConstant: buttonSize),
            shieldButton.heightAnchor.constraint(equalToConstant: buttonSize),
        ])

        // Wire up touch events (touch down = pressed, touch up = released)
        thrustButton.addTarget(self, action: #selector(thrustDown), for: .touchDown)
        thrustButton.addTarget(self, action: #selector(thrustUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        leftButton.addTarget(self, action: #selector(leftDown), for: .touchDown)
        leftButton.addTarget(self, action: #selector(leftUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        rightButton.addTarget(self, action: #selector(rightDown), for: .touchDown)
        rightButton.addTarget(self, action: #selector(rightUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        shieldButton.addTarget(self, action: #selector(shieldFire), for: .touchDown)

        // Initially hidden
        showControlButtons(false)
    }

    func makeThrustButton(title: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        button.backgroundColor = color.withAlphaComponent(0.3)
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 2
        button.layer.borderColor = color.withAlphaComponent(0.6).cgColor
        button.isExclusiveTouch = false
        return button
    }

    func showControlButtons(_ show: Bool) {
        let alpha: CGFloat = show ? 0.35 : 0.0
        UIView.animate(withDuration: 0.3) {
            self.thrustButton?.alpha = alpha
            self.leftButton?.alpha = alpha
            self.rightButton?.alpha = alpha
            self.shieldButton?.alpha = alpha
        }
        thrustButton?.isUserInteractionEnabled = show
        leftButton?.isUserInteractionEnabled = show
        rightButton?.isUserInteractionEnabled = show
        shieldButton?.isUserInteractionEnabled = show
    }

    // MARK: - Button Actions

    @objc func thrustDown()  { renderer?.input.thrustMain = true;  updateEngineSound() }
    @objc func thrustUp()    { renderer?.input.thrustMain = false; updateEngineSound() }
    @objc func leftDown()    { renderer?.input.thrustLeft = true;  updateEngineSound() }
    @objc func leftUp()      { renderer?.input.thrustLeft = false; updateEngineSound() }
    @objc func rightDown()   { renderer?.input.thrustRight = true; updateEngineSound() }
    @objc func rightUp()     { renderer?.input.thrustRight = false; updateEngineSound() }
    @objc func shieldFire()  { renderer?.deployShieldBlaster() }

    // MARK: - Name Entry (iOS Keyboard)

    func showNameEntry() {
        guard nameEntryContainer == nil else { return }

        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // Anchor near the top so the field stays visible above the keyboard
            // (which covers the bottom ~55 % of the screen in landscape).
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            container.widthAnchor.constraint(equalToConstant: 300),
            container.heightAnchor.constraint(equalToConstant: 60),
        ])

        let textField = UITextField()
        textField.placeholder = "YOUR NAME"
        textField.textColor = .green
        textField.font = UIFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        textField.textAlignment = .center
        textField.autocapitalizationType = .allCharacters
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.returnKeyType = .done
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            textField.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        nameTextField = textField
        nameEntryContainer = container
        textField.becomeFirstResponder()
    }

    func hideNameEntry() {
        nameTextField?.resignFirstResponder()
        nameEntryContainer?.removeFromSuperview()
        nameTextField = nil
        nameEntryContainer = nil
    }

    // MARK: - Music

    func setupMusic() {
        guard let url = Bundle.main.url(forResource: "Lunar Descent Loop", withExtension: "mp3") else {
            print("Music file not found in bundle")
            return
        }
        do {
            musicPlayer = try AVAudioPlayer(contentsOf: url)
            musicPlayer?.numberOfLoops = -1
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

        // Periodic timer for wind and engine sound updates
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

        // Scale volume with wind strength
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
    }
}

// MARK: - UITextFieldDelegate (Name Entry)

extension iOSGameViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // "Done" key pressed — commit the name
        let name = textField.text?.uppercased() ?? ""
        renderer.enteredName = name.isEmpty ? "PLAYER" : String(name.prefix(10))
        renderer.confirmName()
        hideNameEntry()
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        let current = textField.text ?? ""
        guard let stringRange = Range(range, in: current) else { return false }
        let updated = current.replacingCharacters(in: stringRange, with: string).uppercased()
        // Limit to 10 chars, letters and spaces only
        let filtered = String(updated.filter { $0.isLetter || $0 == " " }.prefix(10))
        textField.text = filtered
        // Mirror to renderer for the on-screen vector text display
        renderer.enteredName = filtered
        return false
    }
}
