# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Star a task, either when adding it or later from its touch-and-hold menu or by tapping the star on its tile. Starred tasks always stay at the top of their list. Saved tasks from earlier versions load unstarred.
- A **+** button in the header, left of the options button, opens a quick new-category sheet: type a name and press return, or tap a suggestion. It previews the icon as you type, stays open so several categories can be added in a row, and jumps to the newest one when you finish.

### Changed
- Tabs are now a real pager: swipe sideways anywhere over the list to move to the next or previous tab, for any number of categories. The page follows your finger, and the tab strip and background follow the page. Previously swiping only worked over the title area and empty lists.

### Removed
- Swiping a task tile to reveal Edit and Remove, because it competes with the sideways swipe between tabs. Edit and Remove remain on touch and hold, in the editor, and as VoiceOver actions.

## [0.1.0] - 2026-10-30

First release.

### Added
- Task checklist: add, edit, complete, reopen, reorder, and remove tasks, with Undo for removals.
- Swipe a tile right to left to reveal Edit and Remove; a long pull removes it.
- Completed tasks leave the list after 10 minutes and remain available under Completed tasks, where they can be reopened.
- Categories as tabs: a scrolling strip with one-line names, up to three starred categories listed first, drag over the title area to change tabs, and a per-category background colour that sweeps when you switch.
- Category icons suggested from the name, with a letter badge when nothing matches.
- Empty or fully completed custom categories can be deleted, with Undo.
- Rewards: a drawn checkmark and progress line for each completed task, a milestone card with confetti at 25, 50, 75 and 100 percent, custom haptic patterns, and synthesised chimes. Each milestone is celebrated once per category until new tasks are added.
- An Add Task button that zooms the editor out of itself, and a glow where a new tile lands.
- Liquid Glass design for tiles, cards, and the tab selector, with light and dark appearance.
- Settings for appearance, completed-task visibility, haptics, and sounds.
- Accessibility: Reduce Motion, Reduce Transparency, Dynamic Type, and VoiceOver labels and actions.
- Local-only storage with atomic saves, corrupt-file recovery, migration of older files, and a Keychain backup that restores tasks after the app is deleted and reinstalled.
- Debug launch flags for previewing interactions.

### Known limitations
- Requires Xcode 27 and an iOS 27 deployment target to build; there is no pre-built binary.
- Swiping tabs is only available over the title area and empty lists, because task tiles own the sideways swipe. (Fixed after this release.)
- No iCloud sync, widgets, or reminders.
- Gestures, haptics, VoiceOver, and larger text sizes have had limited hands-on testing; the task logic is covered by the automated checks.

[Unreleased]: https://github.com/The-Great-Open-Source/iOS-Todo/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/The-Great-Open-Source/iOS-Todo/releases/tag/v0.1.0
