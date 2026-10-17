# Spec Delta

## Purpose

Decides which page the device shows: manual navigation with a back history, and automatic switching based on the frontmost application.

## ADDED Requirements

### Requirement: Initial page
On startup and after a config reload that removes the current page, the system SHALL show the page mapped to the frontmost application, or `default_page` when that application has no mapping.

#### Scenario: Start with mapped app in front
- **WHEN** the app starts while Xcode is frontmost and `app_pages` maps Xcode's bundle ID to `xcode`
- **THEN** the device shows the `xcode` page

#### Scenario: Start with unmapped app in front
- **WHEN** the app starts while an unmapped application is frontmost
- **THEN** the device shows `default_page`

### Requirement: Manual navigation history
A `page: <name>` action SHALL push the current page onto a history stack and show the named page. `page: back` SHALL pop the stack and show that page. With an empty stack, `page: back` does nothing. Pressing a page action for the page already shown does nothing.

#### Scenario: Forward and back
- **WHEN** the user is on `home`, presses `page: media`, then presses `page: back`
- **THEN** the device shows `media`, then `home`

#### Scenario: Back with empty history
- **WHEN** the history is empty and the user presses `page: back`
- **THEN** the current page stays

### Requirement: Automatic switching by frontmost app
When the frontmost application changes, the system SHALL show the page mapped to its bundle ID in `app_pages`, or `default_page` when it has no mapping. This switch overrides any page chosen manually before it, and clears the history.

#### Scenario: Mapped app activated
- **WHEN** the user switches to Safari and `app_pages` maps `com.apple.Safari` to `browser`
- **THEN** the device shows `browser` and the history is empty

#### Scenario: Unmapped app activated
- **WHEN** the user switches from Safari to an unmapped application
- **THEN** the device shows `default_page`

#### Scenario: App switch after manual navigation
- **WHEN** the user is in Xcode, navigates manually to `media`, then switches to Safari
- **THEN** the device shows Safari's mapped page, or `default_page` if Safari is unmapped

### Requirement: Manual navigation within an app
A manual page change SHALL persist while the frontmost application stays the same.

#### Scenario: Manual page stays
- **WHEN** the user is in Xcode on page `xcode` and presses `page: media`
- **THEN** the device keeps showing `media` until a page action or a change of frontmost app

### Requirement: Own app ignored
Activation of the controller app itself, for example when opening its menu, SHALL NOT change the current page.

#### Scenario: Menu opened
- **WHEN** the user opens the controller's menu-bar menu
- **THEN** the device keeps showing the current page

### Requirement: Disable automatic switching
The system SHALL let the user turn automatic switching off and on from the menu bar. While it is off, frontmost app changes do not change the page.

#### Scenario: Switching paused
- **WHEN** automatic switching is off and the user switches to a mapped app
- **THEN** the page does not change
