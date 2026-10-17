import AppKit
import SwiftUI

final class DictationController {
    enum State { case idle, recording, processing }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle { didSet { onStateChange?(state) } }

    private let settings = AppSettings.shared
    private let hotkey = HotkeyMonitor()
    private let engine = DictationEngine()
    private let hud = HUDController()
    private var handsFree = false
    private var pressedAt = Date.distantPast
    private var startedAt = Date.distantPast
    private var speakingSeconds: Double = 0
    private var peakLevel: Float = 0
    private var targetApp: NSRunningApplication?
    private var selection: String?
    private var fieldContext: String?
    private var trustTimer: Timer?

    func start() {
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }
        hotkey.onOtherKey = { [weak self] in self?.otherKeyWhileHeld() }
        hotkey.onEscape = { [weak self] in self?.cancel(silent: false) }
        hotkey.onPasteLast = { [weak self] in
            // Give the user a moment to release ⌃⌥ so they don't combine with the synthetic ⌘V.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.pasteLast() }
        }
        engine.onLevel = { [weak self] level in
            guard let self else { return }
            self.peakLevel = max(self.peakLevel, level)
            self.hud.push(level: level)
        }
        engine.onPartial = { [weak self] text in self?.hud.setPartial(text) }
        hotkey.start()

        // Global monitors only start receiving events once Accessibility is granted; re-arm them when it is.
        if !Permissions.accessibilityGranted {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard Permissions.accessibilityGranted else { return }
                timer.invalidate()
                self?.hotkey.start()
            }
        }
    }

    func toggleFromMenu() {
        switch state {
        case .idle: begin(handsFree: true)
        case .recording: stop()
        case .processing: break
        }
    }

    func pasteLast() {
        guard state == .idle, let text = settings.history.first else { return }
        if !TextInserter.insert(text, restoreClipboard: settings.restoreClipboard) {
            hud.flash("Texto copiado — cole com ⌘V (libere a Acessibilidade)")
        }
    }

    private func hotkeyPressed() {
        switch state {
        case .idle:
            pressedAt = Date()
            begin(handsFree: false)
        case .recording where handsFree:
            stop()
        default:
            break
        }
    }

    private func hotkeyReleased() {
        guard state == .recording, !handsFree else { return }
        if Date().timeIntervalSince(pressedAt) < 0.3 {
            handsFree = true
            hud.showListening(handsFree: true, editing: selection != nil)
        } else {
            stop()
        }
    }

    // The hotkey was used as a modifier in a shortcut (e.g. ⌥+letter): drop the recording quietly.
    private func otherKeyWhileHeld() {
        if state == .recording && !handsFree { cancel(silent: true) }
    }

    private func begin(handsFree: Bool) {
        guard Permissions.microphoneGranted, Permissions.speechGranted else {
            hud.flash("Permita microfone e fala em Preferências › Permissões")
            Permissions.requestAll {}
            return
        }
        self.handsFree = handsFree
        targetApp = NSWorkspace.shared.frontmostApplication
        selection = settings.aiReady && settings.editMode ? FocusedText.selection() : nil
        fieldContext = settings.aiReady && settings.fieldContext && selection == nil ? FocusedText.fieldContext() : nil
        peakLevel = 0
        do {
            try engine.start(localeID: settings.language, onDevice: settings.onDevice,
                             vocabulary: settings.vocabulary, micUID: settings.micUID)
        } catch {
            hud.flash(error.localizedDescription)
            return
        }
        startedAt = Date()
        state = .recording
        if settings.playSounds { NSSound(named: settings.soundSet.names.start)?.play() }
        if settings.muteWhileDictating {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                if self?.state == .recording { SystemAudio.mute() }
            }
        }
        hud.showListening(handsFree: handsFree, editing: selection != nil)
    }

    private func stop() {
        guard state == .recording else { return }
        speakingSeconds = Date().timeIntervalSince(startedAt)
        if speakingSeconds < 0.3 {
            cancel(silent: true)
            return
        }
        state = .processing
        SystemAudio.restore()
        if settings.playSounds { NSSound(named: settings.soundSet.names.stop)?.play() }
        hud.showProcessing("Transcrevendo…")
        engine.finish { [weak self] raw in self?.process(raw) }
    }

    private func cancel(silent: Bool) {
        guard state == .recording else { return }
        engine.cancel()
        SystemAudio.restore()
        state = .idle
        if silent { hud.hide() } else { hud.flash("Ditado cancelado") }
    }

    private func process(_ raw: String) {
        var text = PostProcessor.process(raw, settings: settings)
        var send = false
        if settings.sendCommandEnabled && selection == nil {
            (text, send) = PostProcessor.extractSendCommand(text, phrases: settings.sendPhraseList)
        }

        if text.isEmpty {
            state = .idle
            if send {
                TextInserter.pressReturn()
                hud.flash("Enviado")
            } else if let reason = engine.lastErrorMessage {
                hud.flash(reason)
            } else if peakLevel < 0.12 {
                hud.flash("O microfone parece mudo — verifique a entrada de áudio")
            } else {
                hud.flash("Nenhuma fala detectada")
            }
            return
        }

        if let selection {
            hud.showProcessing("Editando seleção…")
            AICleaner.edit(selection, instruction: text, settings: settings) { [weak self] result in
                switch result {
                case .success(let edited):
                    self?.deliver(edited, record: false)
                case .failure(let error):
                    NSLog("VozFlow: edit failed: \(error.localizedDescription)")
                    self?.state = .idle
                    self?.settings.addHistory(text)
                    self?.hud.flash("Não foi possível editar — a seleção ficou intacta")
                }
            }
            return
        }

        guard settings.aiReady else {
            deliver(text, pressEnter: send)
            return
        }
        hud.showProcessing(settings.translateTo.isEmpty ? "Refinando com IA…" : "Traduzindo…")
        AICleaner.clean(text, appName: targetApp?.localizedName, fieldContext: fieldContext, settings: settings) { [weak self] result in
            switch result {
            case .success(let cleaned):
                self?.deliver(cleaned, pressEnter: send)
            case .failure(let error):
                NSLog("VozFlow: AI cleanup failed: \(error.localizedDescription)")
                self?.deliver(text, note: "IA indisponível — texto original inserido", pressEnter: send)
            }
        }
    }

    private func deliver(_ text: String, note: String? = nil, pressEnter: Bool = false, record: Bool = true) {
        state = .idle
        settings.addHistory(text)
        if record {
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            settings.stats.record(words: words, seconds: speakingSeconds)
        }
        if TextInserter.insert(text, restoreClipboard: settings.restoreClipboard) {
            if pressEnter {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { TextInserter.pressReturn() }
            }
            if let note { hud.flash(note) } else if pressEnter { hud.flash("Enviado") } else { hud.hide() }
        } else {
            hud.flash("Texto copiado — cole com ⌘V (libere a Acessibilidade)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = DictationController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(.idle)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.onStateChange = { [weak self] state in self?.updateIcon(state) }
        controller.start()

        Permissions.requestAll { [weak self] in
            if !Permissions.allGranted { self?.openSettings() }
        }
    }

    private func updateIcon(_ state: DictationController.State) {
        let name: String
        switch state {
        case .idle: name = "waveform"
        case .recording: name = "record.circle.fill"
        case .processing: name = "ellipsis.circle"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "VozFlow")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = AppSettings.shared

        let header = NSMenuItem(title: "Segure \(settings.hotkey.label) para ditar", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let stats = settings.stats
        if stats.words > 0 {
            let line = NSMenuItem(title: "\(stats.words) palavras · \(stats.wpm) ppm · 🔥 \(stats.streak) dia(s)", action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }

        let toggleTitle = controller.state == .recording ? "Parar ditado" : "Iniciar ditado (mãos livres)"
        menu.addItem(item(toggleTitle, #selector(toggleDictation)))
        let pasteLast = item("Colar última transcrição  (⌃⌥V)", #selector(pasteLastTranscript))
        pasteLast.isEnabled = !settings.history.isEmpty
        menu.addItem(pasteLast)
        menu.addItem(.separator())

        let historyItem = NSMenuItem(title: "Histórico", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        if settings.history.isEmpty {
            let empty = NSMenuItem(title: "Vazio", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            for text in settings.history.prefix(15) {
                let oneLine = text.replacingOccurrences(of: "\n", with: " ")
                let title = oneLine.count > 60 ? String(oneLine.prefix(60)) + "…" : oneLine
                let entry = item(title, #selector(copyHistory(_:)))
                entry.representedObject = text
                entry.toolTip = "Clique para copiar"
                historyMenu.addItem(entry)
            }
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        let ai = item("Refinar com IA", #selector(toggleAI))
        ai.state = settings.aiEnabled ? .on : .off
        menu.addItem(ai)
        menu.addItem(.separator())
        menu.addItem(item("Preferências…", #selector(openSettings), key: ","))
        if !Permissions.allGranted {
            menu.addItem(item("⚠︎ Conceder permissões…", #selector(openSettings)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Sair do VozFlow", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleDictation() { controller.toggleFromMenu() }

    @objc private func pasteLastTranscript() {
        // Let the menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.controller.pasteLast() }
    }

    @objc private func toggleAI() {
        let settings = AppSettings.shared
        settings.aiEnabled.toggle()
        if settings.aiEnabled && settings.activeKey.isEmpty { openSettings() }
    }

    @objc private func copyHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "VozFlow — Preferências"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        SystemAudio.restore(wait: true)
        NSApp.terminate(nil)
    }
}
