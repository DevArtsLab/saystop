import Cocoa
import AVFoundation

// saystop - a floating Stop/Pause panel for macOS `say` speech output.
//
// Usage modes:
//   saystop [say-args...]        Speak with a floating Stop/Pause panel.
//   saystop --mute               Silence all speech until --unmute.
//   saystop --unmute             Re-enable speech.
//   saystop --mute-status        Show whether speech is muted.
//   saystop --install-shim       Create a `say` shim so every `say` call gets the panel.
//   saystop --uninstall-shim     Remove the shim.
//   saystop --shim-status        Show whether the shim is installed.
//   saystop --version            Print version.
//   saystop --help               Print usage.
//
// Invocations saystop can speak itself (plain text, -v, -r, -f) use
// AVSpeechSynthesizer so Pause/Resume works cleanly. Other invocations run
// as a /usr/bin/say child with a Stop-only panel. Non-speaking invocations
// (-o file output, -v ? voice listing) are exec'd with no UI.

let version = "0.2.0"
let args = Array(CommandLine.arguments.dropFirst())

func stderr(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

func execSay() -> Never {
    let cArgs = (["/usr/bin/say"] + args).map { strdup($0) } + [nil]
    execv("/usr/bin/say", cArgs)
    stderr("saystop: execv /usr/bin/say failed")
    exit(127)
}

func executablePath() -> String {
    var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    var size = UInt32(buf.count)
    _NSGetExecutablePath(&buf, &size)
    let path = String(cString: buf)
    let resolved = path.withCString { realpath($0, nil) }
    defer { free(resolved) }
    return resolved.map { String(cString: $0) } ?? path
}

// First writable bin dir that precedes /usr/bin in PATH.
func shimBinDir() -> String {
    let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    let candidates = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
    for c in candidates {
        guard let idx = pathDirs.firstIndex(of: c), idx < (pathDirs.firstIndex(of: "/usr/bin") ?? .max) else { continue }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: c, isDirectory: &isDir),
           isDir.boolValue, FileManager.default.isWritableFile(atPath: c) {
            return c
        }
    }
    return NSHomeDirectory() + "/.local/bin"
}

func shimPath() -> String { shimBinDir() + "/say" }

// Presence of this file mutes all saystop/shim speech.
func muteFlagPath() -> String {
    NSHomeDirectory() + "/.config/saystop/muted"
}

func isMuted() -> Bool {
    FileManager.default.fileExists(atPath: muteFlagPath())
}

func setMuted(_ muted: Bool) {
    let path = muteFlagPath()
    if muted {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        print("muted: speech silenced until `saystop --unmute`")
    } else {
        try? FileManager.default.removeItem(atPath: path)
        print("unmuted")
    }
}

func installShim() {
    let dir = shimBinDir()
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = shimPath()
    if FileManager.default.fileExists(atPath: path) {
        // Only overwrite if it is one of our shims.
        if let existing = try? String(contentsOfFile: path, encoding: .utf8),
           !existing.contains("saystop") {
            stderr("saystop: \(path) exists and is not a saystop shim; not overwriting")
            exit(1)
        }
    }
    let script = "#!/bin/sh\n# saystop shim: gives every `say` call a floating stop button.\n# Remove this file or use /usr/bin/say directly to bypass.\n[ -f \"$HOME/.config/saystop/muted\" ] && exit 0\nexec \"\(executablePath())\" \"$@\"\n"
    do {
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        print("Installed shim at \(path)")
    } catch {
        stderr("saystop: failed to write shim: \(error.localizedDescription)")
        exit(1)
    }
}

func uninstallShim() {
    let path = shimPath()
    if let existing = try? String(contentsOfFile: path, encoding: .utf8),
       existing.contains("saystop") {
        try? FileManager.default.removeItem(atPath: path)
        print("Removed shim at \(path)")
    } else {
        print("No saystop shim found at \(path)")
    }
}

func shimStatus() {
    let path = shimPath()
    if let existing = try? String(contentsOfFile: path, encoding: .utf8),
       existing.contains("saystop") {
        print("shim installed: \(path)")
    } else {
        print("shim not installed (checked \(path))")
    }
}

func usage() {
    print("""
    saystop \(version) - a floating stop button for macOS `say`

    Usage:
      saystop [say-args...]    Speak text with a floating Stop/Pause panel
      saystop --mute           Silence all speech until --unmute
      saystop --unmute         Re-enable speech
      saystop --mute-status    Show mute state
      saystop --install-shim   Shim `say` so every call gets the button
      saystop --uninstall-shim Remove the shim
      saystop --shim-status    Show shim status
      saystop --version        Print version
      saystop --help           Show this help

    All other arguments are passed to /usr/bin/say.
    """)
}

switch args.first {
case "--version": print(version); exit(0)
case "--help", "-h": usage(); exit(0)
case "--mute": setMuted(true); exit(0)
case "--unmute": setMuted(false); exit(0)
case "--mute-status": print(isMuted() ? "muted" : "not muted"); exit(0)
case "--install-shim": installShim(); exit(0)
case "--uninstall-shim": uninstallShim(); exit(0)
case "--shim-status": shimStatus(); exit(0)
default: break
}

// Bypass the UI for invocations that produce no audible speech.
var bypass = false
for (i, a) in args.enumerated() {
    if a == "-o" || a == "--output-file" || a.hasPrefix("--output-file=") { bypass = true }
    if (a == "-v" || a == "--voice") && i + 1 < args.count && args[i + 1] == "?" { bypass = true }
    if a == "--voice=?" { bypass = true }
}
if bypass { execSay() }

// Muted invocations exit silently. Non-speaking invocations above are exempt.
if isMuted() { exit(0) }

// MARK: - Request parsing

// Invocations saystop can speak itself get a Stop/Pause panel.
struct SpeechRequest {
    var text = ""
    var voice: String?
    var wpm: Float?
}

func readStdinText() -> String {
    String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

// Returns nil for any argument saystop cannot map to AVSpeechSynthesizer.
func parseRequest() -> SpeechRequest? {
    var req = SpeechRequest()
    var words: [String] = []
    var i = 0
    func takeValue() -> String? {
        i += 1
        return i < args.count ? args[i] : nil
    }
    while i < args.count {
        let a = args[i]
        if a == "-v" || a == "--voice" {
            guard let v = takeValue() else { return nil }
            req.voice = v
        } else if a.hasPrefix("--voice=") {
            req.voice = String(a.dropFirst("--voice=".count))
        } else if a == "-r" || a == "--rate" {
            guard let v = takeValue(), let r = Float(v) else { return nil }
            req.wpm = r
        } else if a.hasPrefix("--rate=") {
            guard let r = Float(a.dropFirst("--rate=".count)) else { return nil }
            req.wpm = r
        } else if a == "-f" || a == "--input-file" {
            guard let path = takeValue() else { return nil }
            let content = path == "-" ? readStdinText() : try? String(contentsOfFile: path, encoding: .utf8)
            guard let text = content else { return nil }
            words.append(text)
        } else if a.hasPrefix("-") {
            return nil
        } else {
            words.append(a)
        }
        i += 1
    }
    // `say` reads stdin when given no text.
    if words.isEmpty { words.append(readStdinText()) }
    req.text = words.joined(separator: " ")
    return req
}

// MARK: - Panel

// Panel width is derived from these so margins stay even on both sides.
let panelMargin: CGFloat = 12
let panelHeight: CGFloat = 48
let buttonWidth: CGFloat = 76
let buttonHeight: CGFloat = 26
let buttonGap: CGFloat = 8

final class SpeechPanel: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private weak var pauseButton: NSButton?
    private let onStop: () -> Void
    private var onTogglePause: ((Bool) -> Void)?
    private var paused = false

    init(hasPause: Bool, onStop: @escaping () -> Void, onTogglePause: ((Bool) -> Void)? = nil) {
        self.onStop = onStop
        self.onTogglePause = onTogglePause
        let count = hasPause ? 2 : 1
        let width = panelMargin * 2 + buttonWidth * CGFloat(count) + buttonGap * CGFloat(count - 1)
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: panelHeight),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "Say"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        self.panel = p
        super.init()
        p.delegate = self
        var x = panelMargin
        addButton("Stop", action: #selector(stopPressed), x: &x)
        if hasPause {
            pauseButton = addButton("Pause", action: #selector(pausePressed), x: &x)
        }
    }

    @discardableResult
    private func addButton(_ title: String, action: Selector, x: inout CGFloat) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.frame = NSRect(x: x, y: panelMargin, width: buttonWidth, height: buttonHeight)
        panel.contentView?.addSubview(b)
        x += buttonWidth + buttonGap
        return b
    }

    func show() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let stagger = CGFloat(getpid() % 6) * 64
            panel.setFrameOrigin(NSPoint(
                x: f.midX - panel.frame.width / 2,
                y: f.maxY - panel.frame.height - 8 - stagger
            ))
        }
        panel.orderFrontRegardless()
    }

    @objc private func stopPressed() { onStop() }

    @objc private func pausePressed() {
        guard let toggle = onTogglePause else { return }
        paused.toggle()
        toggle(paused)
        pauseButton?.title = paused ? "Resume" : "Pause"
    }

    func windowWillClose(_ notification: Notification) { onStop() }
}

// MARK: - Speech modes

final class SynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let req = parseRequest(), !req.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    // In-process speech: Pause suspends cleanly at word boundaries.
    let synth = AVSpeechSynthesizer()
    let delegate = SynthDelegate()
    synth.delegate = delegate

    let controller = SpeechPanel(
        hasPause: true,
        onStop: {
            synth.stopSpeaking(at: .immediate)
            NSApp.terminate(nil)
        },
        onTogglePause: { wantPause in
            if wantPause {
                _ = synth.pauseSpeaking(at: .word)
            } else {
                _ = synth.continueSpeaking()
            }
        }
    )
    controller.show()

    let utterance = AVSpeechUtterance(string: req.text)
    if let name = req.voice {
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if utterance.voice == nil {
            stderr("saystop: unknown voice '\(name)', using default")
        }
    }
    if let wpm = req.wpm {
        // `say -r` is words per minute (~180 is its default) while
        // AVSpeechUtterance rate is 0...1 with 0.5 as the default.
        utterance.rate = min(max(wpm / 360, AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
    }
    synth.speak(utterance)

    app.run()
    _ = delegate   // keep delegate and controller alive for the run loop
    _ = controller
    exit(0)
}

// Fallback: flags saystop cannot speak itself run as a `say` child process
// with a Stop-only panel.
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
proc.arguments = args
proc.standardInput = FileHandle.standardInput
proc.standardOutput = FileHandle.standardOutput
proc.standardError = FileHandle.standardError
do { try proc.run() } catch {
    stderr("saystop: failed to run /usr/bin/say: \(error)")
    exit(127)
}

let controller = SpeechPanel(hasPause: false, onStop: {
    if proc.isRunning { proc.terminate() }
    NSApp.terminate(nil)
})
controller.show()

proc.terminationHandler = { _ in
    DispatchQueue.main.async { NSApp.terminate(nil) }
}

app.run()
_ = controller // keep the delegate alive for the run loop
exit(proc.terminationStatus)
