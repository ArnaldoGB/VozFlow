import AVFoundation
import Speech

/// `VozFlow --diagnose`: synthesizes a sample phrase, runs it through speech recognition
/// (on-device and server) and writes a report to ~/Library/Logs/VozFlow-diagnostico.txt.
enum Diagnostics {
    static func run() {
        var lines: [String] = []
        let settings = AppSettings.shared
        let locale = Locale(identifier: settings.language)
        lines.append("VozFlow diagnóstico — \(Date())")
        lines.append("Idioma: \(settings.language) | no dispositivo: \(settings.onDevice) | mic: \(settings.micUID.isEmpty ? "padrão" : settings.micUID)")
        lines.append("Autorização fala: \(SFSpeechRecognizer.authorizationStatus().rawValue) (3 = autorizado) | microfone: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3 = autorizado)")

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            lines.append("ERRO: SFSpeechRecognizer não suporta \(settings.language)")
            write(lines)
            return
        }
        lines.append("Disponível: \(recognizer.isAvailable) | suporta no dispositivo: \(recognizer.supportsOnDeviceRecognition)")
        lines.append("Microfones: \(AudioDevices.inputDevices().map(\.name))")

        let voice = settings.language.hasPrefix("pt") ? "Luciana" : "Samantha"
        let sample = FileManager.default.temporaryDirectory.appendingPathComponent("vozflow-sample.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", sample.path, "Olá, este é um teste do ditado por voz."]
        try? say.run()
        say.waitUntilExit()
        lines.append("Amostra (\(voice)): \(FileManager.default.fileExists(atPath: sample.path) ? "ok" : "falhou")")

        for onDevice in [true, false] {
            let request = SFSpeechURLRecognitionRequest(url: sample)
            request.requiresOnDeviceRecognition = onDevice
            request.addsPunctuation = true
            var done = false
            var outcome = "tempo esgotado"
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    let ns = error as NSError
                    outcome = "ERRO \(ns.domain) \(ns.code): \(ns.localizedDescription)"
                    done = true
                } else if let result, result.isFinal {
                    outcome = "OK: \"\(result.bestTranscription.formattedString)\""
                    done = true
                }
            }
            let deadline = Date().addingTimeInterval(20)
            while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            task.cancel()
            lines.append("\(onDevice ? "No dispositivo" : "Servidor Apple"): \(outcome)")
        }
        // Same path as a live dictation: audio arrives as buffers; on-device first, then replay to the server.
        if let file = try? AVAudioFile(forReading: sample) {
            var chunks: [AVAudioPCMBuffer] = []
            while file.framePosition < file.length,
                  let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024),
                  (try? file.read(into: chunk)) != nil, chunk.frameLength > 0 {
                chunks.append(chunk)
            }
            for onDevice in [true, false] {
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.requiresOnDeviceRecognition = onDevice
                request.addsPunctuation = true
                chunks.forEach(request.append)
                request.endAudio()
                var done = false
                var outcome = "tempo esgotado"
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        let ns = error as NSError
                        outcome = "ERRO \(ns.domain) \(ns.code)"
                        done = true
                    } else if let result, result.isFinal {
                        outcome = "OK: \"\(result.bestTranscription.formattedString)\""
                        done = true
                    }
                }
                let deadline = Date().addingTimeInterval(20)
                while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
                task.cancel()
                lines.append("Buffers \(chunks.count)x — \(onDevice ? "no dispositivo" : "reenvio ao servidor"): \(outcome)")
            }
        }
        write(lines)
    }

    private static func write(_ lines: [String]) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/VozFlow-diagnostico.txt")
        try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
