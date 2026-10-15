import Cocoa

// saystop - a floating stop button for macOS `say` speech output.
//
// Usage modes:
//   saystop [say-args...]        Speak with a floating Stop button.
//   saystop --install-shim       Create a `say` shim so every `say` call gets the button.
//   saystop --uninstall-shim     Remove the shim.
//   saystop --shim-status        Show whether the shim is installed.
//   saystop --version            Print version.
//   saystop --help               Print usage.
//
// Non-speaking say invocations (-o file output, -v ? voice listing)
// are exec'd directly with no UI.

let version = "0.1.0"
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
    let script = "#!/bin/sh\n# saystop shim: gives every `say` call a floating stop button.\n# Remove this file or use /usr/bin/say directly to bypass.\nexec \"\(executablePath())\" \"$@\"\n"
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
      saystop [say-args...]    Speak text with a floating Stop button
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

final class StopHandler: NSObject, NSWindowDelegate {
    let proc: Process
    init(_ proc: Process) { self.proc = proc }
    @objc func stop() {
        if proc.isRunning { proc.terminate() }
        NSApp.terminate(nil)
    }
    func windowWillClose(_ notification: Notification) { stop() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let handler = StopHandler(proc)
let size = NSRect(x: 0, y: 0, width: 170, height: 56)
let panel = NSPanel(
    contentRect: size,
    styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
    backing: .buffered,
    defer: false
)
panel.title = "Say"
panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.delegate = handler
panel.isReleasedWhenClosed = false

let button = NSButton(title: "Stop speaking", target: handler, action: #selector(StopHandler.stop))
button.bezelStyle = .rounded
button.frame = NSRect(x: (size.width - 126) / 2, y: 12, width: 126, height: 26)
panel.contentView?.addSubview(button)

if let screen = NSScreen.main {
    let f = screen.visibleFrame
    let stagger = CGFloat(getpid() % 6) * 64
    panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 8 - stagger))
}
panel.orderFrontRegardless()

proc.terminationHandler = { _ in
    DispatchQueue.main.async { NSApp.terminate(nil) }
}

_ = handler // keep the target alive for the run loop
app.run()
exit(proc.terminationStatus)
