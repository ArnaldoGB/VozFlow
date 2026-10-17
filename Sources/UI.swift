import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Floating HUD

final class HUDState: ObservableObject {
    enum Mode: Equatable {
        case listening(handsFree: Bool, editing: Bool)
        case processing(String)
        case message(String)
    }

    @Published var mode: Mode = .message("")
    @Published var levels: [CGFloat] = Array(repeating: 0.05, count: 18)
    @Published var partial = ""
}

struct HUDView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule().fill(Color.black.opacity(0.85)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .foregroundColor(.white)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch state.mode {
        case .listening(let handsFree, let editing):
            Circle().fill(editing ? Color.blue : Color.red).frame(width: 8, height: 8)
            HStack(spacing: 3) {
                ForEach(state.levels.indices, id: \.self) { i in
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: 3, height: 4 + state.levels[i] * 20)
                }
            }
            .animation(.linear(duration: 0.08), value: state.levels)
            Text(state.partial.isEmpty ? label(handsFree: handsFree, editing: editing) : state.partial)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 300, alignment: .leading)
        case .processing(let text):
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 12, weight: .medium))
        case .message(let text):
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
        }
    }

    private func label(handsFree: Bool, editing: Bool) -> String {
        if editing { return "Diga a alteração" }
        return handsFree ? "Mãos livres" : "Ouvindo"
    }
}

final class HUDController {
    private let state = HUDState()
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 520, height: 56)

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
        return panel
    }()

    func showListening(handsFree: Bool, editing: Bool) {
        if case .listening = state.mode {} else {
            state.levels = Array(repeating: 0.05, count: state.levels.count)
            state.partial = ""
        }
        state.mode = .listening(handsFree: handsFree, editing: editing)
        present()
    }

    func showProcessing(_ text: String) {
        state.mode = .processing(text)
        present()
    }

    func flash(_ text: String) {
        state.mode = .message(text)
        present()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    func push(level: Float) {
        guard case .listening = state.mode else { return }
        state.levels.removeFirst()
        state.levels.append(CGFloat(level))
    }

    func setPartial(_ text: String) {
        guard case .listening = state.mode else { return }
        state.partial = text
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
        state.mode = .message("")
    }

    private func present() {
        hideWork?.cancel()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 28))
        }
        panel.orderFrontRegardless()
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var tab = "geral"

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(settings: settings).tabItem { Label("Geral", systemImage: "gearshape") }.tag("geral")
            AITab(settings: settings).tabItem { Label("IA", systemImage: "sparkles") }.tag("ia")
            DictionaryTab(settings: settings).tabItem { Label("Dicionário", systemImage: "character.book.closed") }.tag("dicionario")
            StatsTab(settings: settings).tabItem { Label("Estatísticas", systemImage: "chart.bar") }.tag("estatisticas")
            HistoryTab(settings: settings).tabItem { Label("Histórico", systemImage: "clock") }.tag("historico")
            PermissionsTab().tabItem { Label("Permissões", systemImage: "lock.shield") }.tag("permissoes")
        }
        .padding(16)
        .frame(width: 640, height: 560)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    // Loaded in onAppear: these query the system and must not run on every view rebuild.
    @State private var launchAtLogin = false
    @State private var devices: [InputDevice] = []

    var body: some View {
        Form {
            Section {
                Picker("Idioma", selection: $settings.language) {
                    ForEach(supportedLanguages) { Text($0.label).tag($0.id) }
                }
                Picker("Tecla de atalho", selection: $settings.hotkey) {
                    ForEach(Hotkey.allCases) { Text($0.label).tag($0) }
                }
                Picker("Microfone", selection: $settings.micUID) {
                    Text("Padrão do sistema").tag("")
                    ForEach(devices, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                Text("Segure a tecla, fale e solte para inserir o texto. Um toque rápido ativa o modo mãos livres; toque de novo para terminar. Esc cancela. ⌃⌥V cola a última transcrição.")
                    .font(.callout).foregroundColor(.secondary)
            }
            Section("Comando de envio") {
                Toggle("Terminar com uma frase de envio pressiona Enter", isOn: $settings.sendCommandEnabled)
                TextField("Frases (separadas por vírgula)", text: $settings.sendPhrases)
                    .disabled(!settings.sendCommandEnabled)
                Text("Ex.: \"Chego em 10 minutos, envia agora\" cola \"Chego em 10 minutos\" e envia a mensagem.")
                    .font(.callout).foregroundColor(.secondary)
            }
            Section("Som e comportamento") {
                Toggle("Sons de início e fim", isOn: $settings.playSounds)
                Picker("Conjunto de sons", selection: $settings.soundSet) {
                    ForEach(SoundSet.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.playSounds)
                .onChange(of: settings.soundSet) { _, set in NSSound(named: set.names.start)?.play() }
                Toggle("Silenciar o som do Mac enquanto dita", isOn: $settings.muteWhileDictating)
                Toggle("Reconhecimento no próprio Mac (offline, privado)", isOn: $settings.onDevice)
                if settings.onDevice && DictationEngine.onDeviceUnavailable {
                    Text("O modo offline exige o Ditado do macOS ativado (Ajustes do Sistema › Teclado › Ditado). Enquanto isso, o VozFlow usa o servidor da Apple automaticamente.")
                        .font(.callout).foregroundColor(.orange)
                }
                Toggle("Restaurar a área de transferência depois de colar", isOn: $settings.restoreClipboard)
                Toggle("Abrir ao iniciar sessão", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {}
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            devices = AudioDevices.inputDevices()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct AITab: View {
    @ObservedObject var settings: AppSettings
    @State private var testOutput = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Toggle("Refinar o texto com IA", isOn: $settings.aiEnabled)
                Picker("Provedor", selection: $settings.aiProvider) {
                    ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                }
                if settings.aiProvider == .claude {
                    SecureField("Chave da API Anthropic", text: $settings.apiKey)
                    Picker("Modelo", selection: $settings.aiModel) {
                        ForEach(aiModels, id: \.id) { Text($0.label).tag($0.id) }
                    }
                } else {
                    SecureField("Chave da API Gemini", text: $settings.geminiKey)
                    Picker("Modelo", selection: $settings.geminiModel) {
                        ForEach(geminiModels, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    Text("No plano gratuito da API Gemini, o Google pode usar o texto enviado para melhorar os produtos dele. Evite ditar dados sensíveis ou use uma chave com faturamento ativo.")
                        .font(.callout).foregroundColor(.orange)
                }
                Picker("Estilo", selection: $settings.aiStyle) {
                    ForEach(CleanupStyle.allCases) { Text($0.label).tag($0) }
                }
                Picker("Traduzir para", selection: $settings.translateTo) {
                    ForEach(translationTargets, id: \.id) { Text($0.label).tag($0.id) }
                }
                HStack {
                    Button(testing ? "Testando…" : "Testar") { runTest() }
                        .disabled(testing || settings.activeKey.isEmpty)
                    Text(testOutput).font(.callout).foregroundColor(.secondary).textSelection(.enabled)
                }
            }
            Section("Instruções personalizadas") {
                TextEditor(text: $settings.customInstructions)
                    .font(.body)
                    .frame(height: 70)
                Text("Preferências de estilo aplicadas a todo ditado. Ex.: \"Use 'você', nunca 'tu'. Evite ponto de exclamação. Assine e-mails como Arnaldo.\"")
                    .font(.callout).foregroundColor(.secondary)
            }
            Section("Recursos com IA") {
                Toggle("Modo edição: selecione um texto, segure a tecla e diga a alteração", isOn: $settings.editMode)
                Toggle("Usar o texto já digitado no campo como contexto", isOn: $settings.fieldContext)
                Text("O contexto melhora nomes e tom, mas envia à API até 1.500 caracteres do campo em foco (campos de senha nunca são lidos). Só o texto vai para o provedor de IA, nunca o áudio. Se a IA falhar, o texto original é inserido.")
                    .font(.callout).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func runTest() {
        testing = true
        testOutput = ""
        let sample = "é tipo assim né eu queria saber se amanhã você pode vir aqui às duas não quer dizer às três da tarde"
        AICleaner.clean(sample, appName: "Mail", fieldContext: nil, settings: settings) { result in
            testing = false
            switch result {
            case .success(let text): testOutput = text
            case .failure(let error): testOutput = "Erro: \(error.localizedDescription)"
            }
        }
    }
}

private struct DictionaryTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("""
            Uma entrada por linha:
            • Palavra sozinha → vocabulário (nomes, siglas, jargões).
            • errado => certo → substituição automática.
            • atalho => texto longo → snippet; use \\n para quebrar linha (ex.: minha assinatura => Abraços,\\nArnaldo).
            Comandos de voz: "nova linha", "novo parágrafo".
            """)
                .font(.callout).foregroundColor(.secondary)
            TextEditor(text: $settings.dictionary)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
        .padding(8)
    }
}

private struct StatsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let stats = settings.stats
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                tile("\(stats.words)", "palavras ditadas", "text.word.spacing")
                tile("\(stats.wpm)", "palavras por minuto", "speedometer")
            }
            HStack(spacing: 12) {
                tile(formatMinutes(stats.minutesSaved), "tempo economizado", "hourglass")
                tile("\(stats.streak)", stats.streak == 1 ? "dia seguido" : "dias seguidos", "flame")
            }
            Text("\(stats.dictations) ditados. O tempo economizado compara com digitar a \(Int(UsageStats.typingWPM)) palavras por minuto.")
                .font(.callout).foregroundColor(.secondary)
            Spacer()
            Button("Zerar estatísticas") { settings.stats = UsageStats() }
        }
        .padding(12)
    }

    private func tile(_ value: String, _ caption: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundColor(.accentColor)
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(caption).font(.callout).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func formatMinutes(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

private struct PermissionsTab: View {
    @State private var microphone = false
    @State private var speech = false
    @State private var accessibility = false
    @State private var timer: Timer?

    var body: some View {
        Form {
            row("Microfone", granted: microphone) {
                Permissions.requestMicrophone { _ in refresh() }
                Permissions.openPrivacyPane("Privacy_Microphone")
            }
            row("Reconhecimento de fala", granted: speech) {
                Permissions.requestSpeech { _ in refresh() }
                Permissions.openPrivacyPane("Privacy_SpeechRecognition")
            }
            row("Acessibilidade (atalho global, colar texto e modo edição)", granted: accessibility) {
                Permissions.promptAccessibility()
                Permissions.openPrivacyPane("Privacy_Accessibility")
            }
            Text("Se o atalho não responder depois de liberar a Acessibilidade, remova o VozFlow da lista, adicione de novo e reabra o app.")
                .font(.callout).foregroundColor(.secondary)
        }
        .formStyle(.grouped)
        // Poll only while this tab is visible, and only touch state when something actually changed.
        .onAppear {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in refresh() }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func refresh() {
        let mic = Permissions.microphoneGranted, sp = Permissions.speechGranted, ax = Permissions.accessibilityGranted
        if mic != microphone { microphone = mic }
        if sp != speech { speech = sp }
        if ax != accessibility { accessibility = ax }
    }

    private func row(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(granted ? .green : .orange)
            Text(title)
            Spacer()
            if !granted { Button("Permitir…", action: action) }
        }
    }
}

private struct HistoryTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading) {
            if settings.history.isEmpty {
                Spacer()
                Text("Nenhum ditado ainda.").foregroundColor(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(Array(settings.history.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top) {
                        Text(text).textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                            .help("Copiar")
                    }
                }
                Button("Limpar histórico") { settings.history = [] }
            }
        }
        .padding(8)
    }
}
