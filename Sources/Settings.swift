import AppKit
import Security

enum Hotkey: String, CaseIterable, Identifiable {
    case rightOption, rightCommand, rightControl, fn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightOption: return "⌥ Option direito"
        case .rightCommand: return "⌘ Command direito"
        case .rightControl: return "⌃ Control direito"
        case .fn: return "fn / 🌐 Globo"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .fn: return 63
        }
    }

    // Device-dependent masks (IOKit NX_DEVICER*KEYMASK) so the left-hand key never triggers dictation.
    func isDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        let raw = flags.rawValue
        switch self {
        case .rightOption: return raw & 0x40 != 0
        case .rightCommand: return raw & 0x10 != 0
        case .rightControl: return raw & 0x2000 != 0
        case .fn: return flags.contains(.function)
        }
    }
}

enum CleanupStyle: String, CaseIterable, Identifiable {
    case natural, formal, casual, literal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: return "Natural"
        case .formal: return "Formal / profissional"
        case .casual: return "Casual / chat"
        case .literal: return "Literal (mínimo de edição)"
        }
    }

    var instruction: String {
        switch self {
        case .natural: return "Neutral, natural writing that keeps the speaker's own voice and word choice."
        case .formal: return "Professional and polished, suitable for work email and documents."
        case .casual: return "Relaxed chat style: short sentences, friendly tone, light punctuation."
        case .literal: return "Minimal edits: only punctuation, capitalization and filler-word removal; keep the wording exactly as spoken."
        }
    }
}

enum SoundSet: String, CaseIterable, Identifiable {
    case classic, soft, glass, morse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Clássico"
        case .soft: return "Suave"
        case .glass: return "Vidro"
        case .morse: return "Morse"
        }
    }

    var names: (start: String, stop: String) {
        switch self {
        case .classic: return ("Tink", "Pop")
        case .soft: return ("Purr", "Bottle")
        case .glass: return ("Glass", "Submarine")
        case .morse: return ("Morse", "Frog")
        }
    }
}

struct Language: Identifiable, Hashable {
    let id: String
    let label: String
}

let supportedLanguages: [Language] = [
    Language(id: "pt-BR", label: "Português (Brasil)"),
    Language(id: "pt-PT", label: "Português (Portugal)"),
    Language(id: "en-US", label: "English (US)"),
    Language(id: "en-GB", label: "English (UK)"),
    Language(id: "es-ES", label: "Español (España)"),
    Language(id: "es-MX", label: "Español (México)"),
    Language(id: "fr-FR", label: "Français"),
    Language(id: "it-IT", label: "Italiano"),
    Language(id: "de-DE", label: "Deutsch"),
]

/// Output languages for AI translation; the id is the English name sent to the model ("" = off).
let translationTargets: [(id: String, label: String)] = [
    ("", "Desligada (manter o idioma falado)"),
    ("Brazilian Portuguese", "Português (Brasil)"),
    ("English", "Inglês"),
    ("Spanish", "Espanhol"),
    ("French", "Francês"),
    ("Italian", "Italiano"),
    ("German", "Alemão"),
    ("Japanese", "Japonês"),
    ("Simplified Chinese", "Chinês (simplificado)"),
]

enum AIProvider: String, CaseIterable, Identifiable {
    case claude, gemini

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .gemini: return "Gemini (Google)"
        }
    }
}

let aiModels: [(id: String, label: String)] = [
    ("claude-opus-5-5", "Claude Opus 5.5 (melhor qualidade)"),
    ("claude-sonnet-5-5", "Claude Sonnet 5.5 (equilíbrio)"),
    ("claude-haiku-5-5", "Claude Haiku 5.5 (mais rápido e barato)"),
]

// "-latest" aliases track Google's current release, so the app keeps working as models are renamed.
let geminiModels: [(id: String, label: String)] = [
    ("gemini-flash-lite-latest", "Gemini Flash-Lite (mais rápido)"),
    ("gemini-flash-latest", "Gemini Flash (melhor qualidade)"),
    ("gemini-pro-latest", "Gemini Pro (requer plano pago)"),
]

struct UsageStats: Codable {
    var words = 0
    var seconds: Double = 0
    var dictations = 0
    var days: [String] = []

    static let typingWPM = 40.0

    var wpm: Int { seconds > 1 ? Int(Double(words) / (seconds / 60)) : 0 }

    /// Minutes saved versus typing the same words at `typingWPM`.
    var minutesSaved: Int { max(0, Int(Double(words) / Self.typingWPM - seconds / 60)) }

    var streak: Int {
        let calendar = Calendar.current
        let set = Set(days)
        var day = Date()
        if !set.contains(Self.key(day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), set.contains(Self.key(yesterday)) else { return 0 }
            day = yesterday
        }
        var count = 0
        while set.contains(Self.key(day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    mutating func record(words: Int, seconds: Double) {
        self.words += words
        self.seconds += seconds
        dictations += 1
        let today = Self.key(Date())
        if days.last != today { days.append(today) }
        if days.count > 400 { days.removeFirst(days.count - 400) }
    }

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var hotkey: Hotkey { didSet { defaults.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var micUID: String { didSet { defaults.set(micUID, forKey: "micUID") } }
    @Published var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    @Published var soundSet: SoundSet { didSet { defaults.set(soundSet.rawValue, forKey: "soundSet") } }
    @Published var muteWhileDictating: Bool { didSet { defaults.set(muteWhileDictating, forKey: "muteWhileDictating") } }
    @Published var onDevice: Bool { didSet { defaults.set(onDevice, forKey: "onDevice") } }
    @Published var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: "restoreClipboard") } }
    @Published var sendCommandEnabled: Bool { didSet { defaults.set(sendCommandEnabled, forKey: "sendCommandEnabled") } }
    @Published var sendPhrases: String { didSet { defaults.set(sendPhrases, forKey: "sendPhrases") } }
    @Published var aiEnabled: Bool { didSet { defaults.set(aiEnabled, forKey: "aiEnabled") } }
    @Published var aiProvider: AIProvider { didSet { defaults.set(aiProvider.rawValue, forKey: "aiProvider") } }
    @Published var aiModel: String { didSet { defaults.set(aiModel, forKey: "aiModel") } }
    @Published var geminiModel: String { didSet { defaults.set(geminiModel, forKey: "geminiModel") } }
    @Published var aiStyle: CleanupStyle { didSet { defaults.set(aiStyle.rawValue, forKey: "aiStyle") } }
    @Published var customInstructions: String { didSet { defaults.set(customInstructions, forKey: "customInstructions") } }
    @Published var translateTo: String { didSet { defaults.set(translateTo, forKey: "translateTo") } }
    @Published var editMode: Bool { didSet { defaults.set(editMode, forKey: "editMode") } }
    @Published var fieldContext: Bool { didSet { defaults.set(fieldContext, forKey: "fieldContext") } }
    @Published var dictionary: String { didSet { defaults.set(dictionary, forKey: "dictionary") } }
    @Published var history: [String] { didSet { defaults.set(history, forKey: "history") } }
    @Published var stats: UsageStats { didSet { defaults.set(try? JSONEncoder().encode(stats), forKey: "stats") } }
    @Published var apiKey: String { didSet { Keychain.save(apiKey, account: Keychain.anthropicAccount) } }
    @Published var geminiKey: String { didSet { Keychain.save(geminiKey, account: Keychain.geminiAccount) } }

    private init() {
        defaults.register(defaults: [
            "language": "pt-BR",
            "hotkey": Hotkey.rightOption.rawValue,
            "micUID": "",
            "playSounds": true,
            "soundSet": SoundSet.classic.rawValue,
            "muteWhileDictating": false,
            "onDevice": true,
            "restoreClipboard": true,
            "sendCommandEnabled": true,
            "sendPhrases": "envia agora, pode enviar, send it, envíalo",
            "aiEnabled": false,
            "aiProvider": AIProvider.claude.rawValue,
            "aiModel": "claude-opus-5-5",
            "geminiModel": "gemini-flash-lite-latest",
            "aiStyle": CleanupStyle.natural.rawValue,
            "customInstructions": "",
            "translateTo": "",
            "editMode": true,
            "fieldContext": false,
            "dictionary": "",
        ])
        language = defaults.string(forKey: "language") ?? "pt-BR"
        hotkey = Hotkey(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .rightOption
        micUID = defaults.string(forKey: "micUID") ?? ""
        playSounds = defaults.bool(forKey: "playSounds")
        soundSet = SoundSet(rawValue: defaults.string(forKey: "soundSet") ?? "") ?? .classic
        muteWhileDictating = defaults.bool(forKey: "muteWhileDictating")
        onDevice = defaults.bool(forKey: "onDevice")
        restoreClipboard = defaults.bool(forKey: "restoreClipboard")
        sendCommandEnabled = defaults.bool(forKey: "sendCommandEnabled")
        sendPhrases = defaults.string(forKey: "sendPhrases") ?? ""
        aiEnabled = defaults.bool(forKey: "aiEnabled")
        aiProvider = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .claude
        aiModel = defaults.string(forKey: "aiModel") ?? "claude-opus-5-5"
        geminiModel = defaults.string(forKey: "geminiModel") ?? "gemini-flash-lite-latest"
        aiStyle = CleanupStyle(rawValue: defaults.string(forKey: "aiStyle") ?? "") ?? .natural
        customInstructions = defaults.string(forKey: "customInstructions") ?? ""
        translateTo = defaults.string(forKey: "translateTo") ?? ""
        editMode = defaults.bool(forKey: "editMode")
        fieldContext = defaults.bool(forKey: "fieldContext")
        dictionary = defaults.string(forKey: "dictionary") ?? ""
        history = defaults.stringArray(forKey: "history") ?? []
        stats = (defaults.data(forKey: "stats")).flatMap { try? JSONDecoder().decode(UsageStats.self, from: $0) } ?? UsageStats()
        apiKey = Keychain.load(account: Keychain.anthropicAccount)
        geminiKey = Keychain.load(account: Keychain.geminiAccount)
    }

    var activeKey: String { aiProvider == .claude ? apiKey : geminiKey }

    var aiReady: Bool { aiEnabled && !activeKey.isEmpty }

    func addHistory(_ text: String) {
        history.insert(text, at: 0)
        if history.count > 30 { history.removeLast(history.count - 30) }
    }

    var sendPhraseList: [String] {
        sendPhrases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var dictionaryLines: [String] {
        dictionary.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// "errado => certo" lines; "\n" in the replacement becomes a line break (useful for snippets).
    var replacements: [(from: String, to: String)] {
        dictionaryLines.compactMap { line in
            guard let range = line.range(of: "=>") ?? line.range(of: "->") else { return nil }
            let from = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let to = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\n", with: "\n")
            return from.isEmpty ? nil : (from, to)
        }
    }

    /// Words the recognizer and the AI should prefer (plain lines only; snippets are not vocabulary).
    var vocabulary: [String] {
        dictionaryLines.filter { $0.range(of: "=>") == nil && $0.range(of: "->") == nil }
    }
}

enum Keychain {
    static let anthropicAccount = "anthropic-api-key"
    static let geminiAccount = "gemini-api-key"

    private static func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "VozFlow",
            kSecAttrAccount as String: account,
        ]
    }

    static func load(account: String) -> String {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String, account: String) {
        SecItemDelete(base(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var item = base(account)
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
