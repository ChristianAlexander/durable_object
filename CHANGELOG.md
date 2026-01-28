# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Versioned migrations for database schema
- Alarm scheduling with two backends:
  - `DurableObject.Scheduler.Polling` - Database-backed polling (default)
  - `DurableObject.Scheduler.Oban` - Oban integration (optional)
- Distribution support via Horde (optional)
- Telemetry instrumentation for storage operations
- Igniter-based installation task (`mix igniter.install durable_object`)
- Object generator task (`mix durable_object.gen.object`)

### Configuration Options

- `repo` - Ecto repo for persistence
- `cluster` - `:local` (default) or `:horde` for distribution
- `scheduler` - Alarm scheduler backend
- `scheduler_opts` - Backend-specific options

[Unreleased]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ChristianAlexander/durable_object/releases/tag/v0.1.0
