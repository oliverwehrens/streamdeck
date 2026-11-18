import DeckConfig
import DeckEditor
import DeckEngine
import DeckPlatformLinux
import DeckRender
import DeckWeb
import Foundation

// Headless Stream Deck daemon for Linux. Logs go to stderr, which systemd sends to the journal.

/// One unbuffered write per line, so lines never interleave or wait in a buffer.
func log(_ line: String) {
    FileHandle.standardError.write(Data("\(line)\n".utf8))
}

let options: WebOptions
switch WebOptions.parse(Array(CommandLine.arguments.dropFirst())) {
case let .success(parsed):
    options = parsed
case let .failure(error):
    log("streamdeckd: \(error)")
    log(WebOptions.usage)
    exit(2)
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
var web: WebEditor?
engine.onStatusChange = { status in
    StatusLog.lines(from: lastStatus, to: status).forEach(log)
    lastStatus = status
    web?.statusChanged(status)
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

/// The config file's latest result, applied to the deck unless the web editor holds it.
var latestUpdate: ConfigWatcher.Update?

@MainActor func showSavedConfig() {
    switch latestUpdate {
    case let .loaded(config): engine.configLoaded(config)
    case let .failed(errors): engine.configFailed(errors)
    case nil: break
    }
}

if options.enabled {
    let editor = ConfigEditor(configURL: configURL)
    editor.loadFromDisk()
    let scheduler = MainQueueScheduler()
    web = WebEditor(editor: editor, engine: engine, tokens: TokenStore(scheduler: scheduler), scheduler: scheduler,
                    log: log, showSavedConfig: showSavedConfig)
}

// DispatchQueue.main keeps updates in order; the main queue is the main actor's executor.
// While a browser edits, file changes go to the editor and the deck keeps showing the draft.
let watcher = ConfigWatcher(url: configURL) { update in
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            latestUpdate = update
            web?.fileChanged()
            if web?.holdsDeck != true { showSavedConfig() }
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

var serverTask: Task<Void, Never>?
if let web {
    serverTask = Task {
        do {
            try await WebServer.run(web: web, host: options.host, port: options.port) { _ in
                DispatchQueue.main.async {
                    for url in options.urls() { log("web editor at \(url)") }
                }
            }
        } catch is CancellationError {
        } catch {
            let message = "Web editor: cannot listen on \(options.host):\(options.port): \(error)"
            log(message)
            engine.setWebProblem(message)
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
            web?.hub.closeAll()
            serverTask?.cancel()
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
