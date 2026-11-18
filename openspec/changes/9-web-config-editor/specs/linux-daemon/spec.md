# Spec Delta

## ADDED Requirements

### Requirement: Web editor service
By default, `streamdeckd` SHALL serve the web editor over HTTP on port 3325 of all network interfaces. `--web-listen <address>:<port>` SHALL change the address and port, and `--no-web` SHALL turn the web editor off. At startup the daemon SHALL log the editor's URLs, one with the host name and one per IPv4 address. If it can't listen, the daemon SHALL log why, show it as a problem, and keep driving the deck.

#### Scenario: Default start
- **WHEN** `streamdeckd` starts without options on a machine named `steammachine`
- **THEN** the journal shows `web editor at http://steammachine.local:3325/` and the same URL for each IPv4 address, and the editor can be reached from the LAN

#### Scenario: Port in use
- **WHEN** another program already listens on port 3325
- **THEN** the deck works as before, the journal says the port is in use, and the status key shows the problem

#### Scenario: Turned off
- **WHEN** the unit runs `streamdeckd --no-web`
- **THEN** nothing listens on the network

### Requirement: Config changes while editing
While the web editor holds the deck, a change to `config.yaml` on disk SHALL go to the editor, following its external-change rules, instead of replacing the preview on the deck. Once the editor releases the deck, the deck SHALL show the config currently in `config.yaml`.

#### Scenario: File edited over ssh during editing
- **WHEN** a browser has unsaved edits and the file is changed over ssh
- **THEN** the deck keeps showing the draft, and the browser asks whether to load the file
