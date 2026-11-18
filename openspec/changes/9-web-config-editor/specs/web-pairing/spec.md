# Spec Delta

## Purpose

Controls which browsers may use the web editor. A config can run shell commands, so a browser gets access only after someone at the deck shows it the pairing code.

## ADDED Requirements

### Requirement: Paired browsers only
Every request that reads or changes the config, the draft, the problems, the key images or the paired-browser list SHALL be refused unless it comes from a paired browser. A browser that isn't paired SHALL see only the pairing screen.

#### Scenario: New browser
- **WHEN** a browser that has never paired opens the editor URL
- **THEN** it shows the pairing screen and no config content

#### Scenario: Direct API call without pairing
- **WHEN** a client that isn't paired sends a request to change a key
- **THEN** the request is refused with status 401 and the draft is unchanged

### Requirement: Pairing code on the deck
When a browser asks to pair, the deck SHALL show a randomly chosen 6-digit code on its keys, together with a Cancel key. Deck keys SHALL run no actions while the code is shown. The code SHALL expire after 2 minutes, when Cancel is pressed, when pairing succeeds, or when another pairing request replaces it. The deck SHALL then return to what it showed before.

#### Scenario: Ask to pair
- **WHEN** the user clicks Pair in a new browser
- **THEN** the deck shows a 6-digit code and a Cancel key, and the browser asks for the code

#### Scenario: Cancel on the deck
- **WHEN** the code is shown and the user presses Cancel on the deck
- **THEN** the deck shows its page again and the code no longer works

#### Scenario: Code expires
- **WHEN** the code was shown 2 minutes ago and hasn't been entered
- **THEN** the deck shows its page again and the code no longer works

#### Scenario: No deck connected
- **WHEN** a browser asks to pair while no deck is connected
- **THEN** the browser says that pairing needs the deck connected, and no code is created

### Requirement: Entering the code
Entering the shown code SHALL pair the browser and give it a token that stays valid until revoked. The browser SHALL keep the token, so it opens the editor directly from then on. After 5 wrong entries, the code SHALL stop working. After 10 wrong entries within 10 minutes, the daemon SHALL refuse pairing for 10 minutes.

#### Scenario: Correct code
- **WHEN** the user types the code shown on the deck
- **THEN** the browser opens the editor, and later visits from that browser open it without pairing

#### Scenario: Wrong code
- **WHEN** the user types a wrong code 5 times
- **THEN** the code stops working and the browser has to ask for a new one

#### Scenario: Guessing across codes
- **WHEN** 10 wrong codes are entered within 10 minutes
- **THEN** pairing requests are refused for the next 10 minutes, and the daemon logs it

### Requirement: Revoking browsers
The editor SHALL list the paired browsers with a name, the pairing date and the last use, and SHALL let the user revoke any of them, including the current one. A revoked browser SHALL be refused from its next request. Deleting the token file and restarting the daemon SHALL revoke all browsers.

#### Scenario: Revoke a lost phone
- **WHEN** the user revokes `Phone` from the laptop
- **THEN** the next request from the phone is refused, and the phone shows the pairing screen

### Requirement: Token storage
The daemon SHALL store only a hash of each token, in a file that only the daemon's user can read, outside the config directory. Pairing and revoking SHALL survive a daemon restart.

#### Scenario: After restart
- **WHEN** a paired browser opens the editor after the daemon restarted
- **THEN** it opens the editor without pairing again

### Requirement: Cross-site requests refused
The daemon SHALL refuse any request that changes state when the request comes from a page on another origin, even with a valid token. Responses SHALL NOT allow other origins to read them.

#### Scenario: Malicious page in the same browser
- **WHEN** a paired browser visits another website that sends a request to the daemon to change a key
- **THEN** the request is refused and the draft is unchanged
