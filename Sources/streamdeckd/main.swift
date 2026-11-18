import DeckConfig
import DeckEngine
import DeckPlatformLinux
import DeckRender
import Foundation

// Headless Stream Deck daemon for Linux. Logs go to stderr, which systemd sends to the journal.

/// One unbuffered write per line, so lines never interleave or wait in a buffer.
func log(_ line: String) {
    FileHandle.standardError.write(Data("\(line)\n".utf8))
}

let configURL = ConfigFile.defaultURL
log("starting, config \(configURL.path)")

let commands = ShellRunner()
let keyboard = UinputKeyboard.create()
let layoutDetection = LayoutDetection()
if let (selection, source) = layoutDetection.detect() {
    log("keyboard layout \(selection.name) (from \(source))")
} else {
    log("keyboard layout us (none configured)")
}

let engine = DeckEngine(
    transport: HidrawTransport(),
    renderer: KeyRenderer(),
    performer: LinuxActionPerformer(commands: commands, keyboard: keyboard),
    commands: commands,
    configDirectory: configURL.deletingLastPathComponent(),
    ownBundleID: "streamdeckd",
    frontmostApp: nil,
    showsProblemsOnDeck: true
)

var lastStatus = DeckEngine.Status()
engine.onStatusChange = { status in
    StatusLog.lines(from: lastStatus, to: status).forEach(log)
    lastStatus = status
}
engine.onStatusKeyPress = {
    StatusLog.allProblems(engine.status).forEach(log)
}

if case let .failure(error) = keyboard {
    engine.setPermissionProblem(error.description)
}

do {
    if try ConfigFile.createStarterIfMissing(at: configURL) { log("created starter config") }
} catch {
    engine.configFailed([ConfigError("cannot create \(configURL.path): \(error.localizedDescription)")])
}

// DispatchQueue.main keeps updates in order; the main queue is the main actor's executor.
let watcher = ConfigWatcher(url: configURL) { update in
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            switch update {
            case let .loaded(config): engine.configLoaded(config)
            case let .failed(errors): engine.configFailed(errors)
            }
        }
    }
}

let resume = ResumeDetector()
resume.start {
    // The device needs a moment after resume before it accepts writes (same as on macOS).
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        MainActor.assumeIsolated {
            log("resumed from suspend, redrawing")
            engine.redrawAll()
        }
    }
}

var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        MainActor.assumeIsolated {
            log("stopping")
            watcher.stop()
            engine.shutdown()
            exit(0)
        }
    }
    source.resume()
    signalSources.append(source)
}

engine.start()
watcher.start()
dispatchMain()
