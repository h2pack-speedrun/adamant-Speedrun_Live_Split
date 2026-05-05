# Changelog

## [Unreleased]

### Changed

- Quick tab minor bug fix
- Single run timer now persists after victory screen
## [1.1.0] - 2026-05-05

### Changed

- Moved game hooks to the ModpackLib hook contract for reload-safe registration.
- Hardened GitHub Actions so Lua validation runs before releases.
- Moved timer HUD rendering onto ModpackLib managed overlays.
- Reworked the module UI around selectable timer columns, live timer rows, split table visibility, split mode, and batch recording controls.
- Updated the packaged README to describe the current player-facing timer and split features.

### Added

- Added IGT, RTA, and LrT column selection for live timer rows and split tables.
- Added biome split tables for Underworld, Surface, and Dream Dive routes.
- Added multi-run batch recording with cumulative IGT/RTA/LrT totals.
- Added Quick Setup content with a simple module enable toggle.
- Added runtime persistence for batch recording intent across reloads.
- Added tests for timer formatting, route rows, batch recording, and UI fallback behavior.

## [1.0.0] - 2026-04-21

Initial release

[unreleased]: https://github.com/h2pack-speedrun/adamant-Speedrun_Timer/compare/1.1.0...HEAD
[1.1.0]: https://github.com/h2pack-speedrun/adamant-Speedrun_Timer/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/h2pack-speedrun/adamant-Speedrun_Timer/compare/634e4468165e8839e160039a7a5d3e751344e5dd...1.0.0
