# Spec Delta

## MODIFIED Requirements

### Requirement: Dynamic keys
For a key with `dynamic`, the system SHALL run `run` through the user's shell every `every` interval while the key's page is shown. When the standard output, after leading whitespace, starts with `{`, it is handled as JSON (see Dynamic key JSON output). Otherwise the first line of standard output, trimmed, replaces the key's `label`. Runs SHALL NOT overlap for the same key.

#### Scenario: Clock key
- **WHEN** a key has `dynamic: { run: "date +%H:%M", every: 30s }` on the current page
- **THEN** the key shows the current time and updates at least every 30 seconds

#### Scenario: Page not shown
- **WHEN** the page containing a dynamic key is not the current page
- **THEN** the key's command is not run

#### Scenario: Slow command
- **WHEN** a dynamic command takes longer than its interval
- **THEN** the next run starts only after the previous one finishes

### Requirement: Dynamic key failure
When a dynamic command exits non-zero, runs longer than 10 seconds, or prints JSON output that is rejected, the system SHALL keep the key's last successful label, icon and background, and mark the key as failed with an error indicator. The menu SHALL show the reason. For a command that runs too long, the system SHALL stop that run.

#### Scenario: Command fails
- **WHEN** the dynamic command exits with status 1
- **THEN** the key keeps its previous label and shows an error indicator until a later run succeeds

#### Scenario: Command hangs
- **WHEN** the dynamic command is still running after 10 seconds
- **THEN** it is terminated and the key shows the error indicator

#### Scenario: Invalid JSON after a good run
- **WHEN** a run printed `{"label":"on","background":"#c08000"}` and the next run prints `{"label":`
- **THEN** the key keeps the label `on` and the background `#c08000`, shows the error indicator, and the menu says the output is not valid JSON

## ADDED Requirements

### Requirement: Dynamic key JSON output
JSON output SHALL be one object with optional fields `label` (string), `icon` (string) and `background` (string `#RRGGBB`). Each present field replaces the key's configured value. Omitted fields keep the configured value. Unknown fields SHALL be ignored. An empty `label` hides the label. Output that is not a JSON object, or a known field with the wrong type or an invalid color, SHALL be rejected.

#### Scenario: Script sets all fields
- **WHEN** a dynamic command prints `{"label":"on","icon":"sf:lightbulb.fill","background":"#c08000"}`
- **THEN** the key shows the `lightbulb.fill` symbol and the label `on` on a `#c08000` background

#### Scenario: Omitted field keeps configured value
- **WHEN** a key is configured with `icon: sf:bitcoinsign.circle` and `background: "#000000"`, and its command prints `{"label":"67250","background":"#802020"}`
- **THEN** the key shows the `bitcoinsign.circle` symbol and the label `67250` on a `#802020` background

#### Scenario: Unknown field
- **WHEN** a dynamic command prints `{"label":"ok","progress":0.5}`
- **THEN** the key shows the label `ok`, and no problem is reported

#### Scenario: Invalid color
- **WHEN** a dynamic command prints `{"background":"yellow"}`
- **THEN** the output is rejected as a failed run, and the menu names the invalid `background` value

#### Scenario: Plain text unchanged
- **WHEN** a dynamic command prints `12:34`
- **THEN** the key's label becomes `12:34`, and its icon and background stay as configured

### Requirement: Dynamic key icon values
The `icon` field in JSON output SHALL accept the same forms as the config: `sf:<name>` for an SF Symbol, or an image file path. A path starting with `~` expands to the home directory. A relative path resolves against the config file's directory. An icon that cannot be loaded SHALL be shown and reported like a missing configured icon.

#### Scenario: Relative image path
- **WHEN** the config lives in `~/.config/streamdeck/` and a dynamic command prints `{"icon":"icons/on.png"}`
- **THEN** the key shows the image `~/.config/streamdeck/icons/on.png`

#### Scenario: Unknown symbol
- **WHEN** a dynamic command prints `{"icon":"sf:no.such.symbol"}`
- **THEN** the key shows the placeholder mark, and the menu bar reports the unknown symbol
