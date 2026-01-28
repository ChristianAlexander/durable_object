# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Lifecycle guide with Mermaid diagrams covering all phases from startup through shutdown
- Mermaid diagram rendering support in ExDoc
- `usage-rules.md` for LLM agent guidance via the usageRules ecosystem

### Changed

- Oban scheduler `oban_instance` option now defaults to `Oban`, matching the common case where apps use a single default Oban instance

### Fixed

- Documentation in `DurableObject.Scheduler` now uses correct option names (`oban_instance` and `oban_queue`) to match the implementation
- Oban scheduler documentation now shows simple default configuration first, with customization options explained separately

## [0.1.4] - 2026-01-27

### Fixed

- Documentation now uses correct `registry_mode` config key instead of `cluster`
- README migration example now uses latest migration version instead of hardcoding `version: 1`
- Installer generates migrations using latest version for `up/0`
- Polling scheduler documentation shows `repo` at top-level config (canonical location)

## [0.1.3] - 2026-01-27

### Fixed

- Oban scheduler `schedule/4` now passes arguments to `Oban.insert/2` in the correct order for named instances

## [0.1.2] - 2026-01-27

### Fixed

- Oban scheduler `cancel/3` and `cancel_all/2` now pass an Ecto query to `Oban.cancel_all_jobs/2` instead of a function, fixing a crash with `Protocol.UndefinedError` for `Ecto.Queryable`

## [0.1.1] - 2026-01-27

### Fixed

- Oban scheduler now uses correct config keys (`oban_instance` and `oban_queue`) to match what the installer generates

## [0.1.0] - 2026-01-27

### Added

- Initial release
- Core Durable Object functionality with GenServer-backed instances
- Spark DSL for declarative object definitions
  - `state` section for defining fields with types and defaults
  - `handlers` section for defining RPC methods
  - `options` section for lifecycle configuration
- Automatic client API generation from handler definitions
- Ecto-based persistence with JSON blob state storage
- Versioned migrations for database schema (v1 creates tables, v2 removes unused locking columns)
- Alarm scheduling with two backends:
  - `DurableObject.Scheduler.Polling` - Database-backed polling (default)
  - `DurableObject.Scheduler.Oban` - Oban integration (optional)
- Distribution support via Horde (optional)
- Telemetry instrumentation for storage operations
- Igniter-based installation task (`mix igniter.install durable_object`)
- Object generator task (`mix durable_object.gen.object`)

### Configuration Options

- `repo` - Ecto repo for persistence
- `registry_mode` - `:local` (default) or `:horde` for distribution
- `scheduler` - Alarm scheduler backend
- `scheduler_opts` - Backend-specific options

[Unreleased]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ChristianAlexander/durable_object/releases/tag/v0.1.0
