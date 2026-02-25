# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Auto-generated DSL reference documentation via `mix spark.cheat_sheets`
- `mix docs` alias now chains `spark.cheat_sheets` → `docs` → `spark.replace_doc_links`
- CI check to verify DSL documentation is up-to-date (`mix spark.cheat_sheets --check`)

### Changed

- State is now returned as a struct (`%MyApp.Counter.State{count: 0}`) instead of a plain atom-keyed map (`%{count: 0}`)
  - The DSL automatically generates a nested `State` struct module from the declared fields and defaults
  - `%{state | field: value}` update syntax continues to work unchanged
  - State is persisted to the database as a plain JSON map (no `__struct__` key)
  - Unknown keys in persisted state are silently dropped on load (forward-compatible with field removal)
  - `get_persisted_state/3` in `DurableObject.Testing` now returns the module's `State` struct
  - **Breaking:** `state[:field]` bracket access no longer works — use `state.field` dot access instead

## [0.2.1] - 2026-02-03

### Added

- `object_keys` option to control how string keys within field values are converted when loading state from JSON
  - `:strings` (default) - leaves keys as strings
  - `:atoms!` - converts to existing atoms only (raises on unknown keys)
  - `:atoms` - creates atoms as needed (use with caution)
  - Configurable per-object in the DSL `options` block, or globally via `config :durable_object, object_keys: :atoms!`
  - DSL setting takes precedence over application config
- `DurableObject.Testing` module with ergonomic test helpers
  - `use DurableObject.Testing, repo: MyApp.Repo` sets up Ecto sandbox and imports helpers
  - Unit testing: `perform_handler/4` and `perform_alarm_handler/3` for testing handler logic in isolation
  - Alarm assertions: `assert_alarm_scheduled/4`, `refute_alarm_scheduled/4`, `all_scheduled_alarms/3`
  - Alarm execution: `fire_alarm/4` to bypass scheduler timing, `drain_alarms/3` for alarm chains
  - State assertion: `assert_persisted/4` for verifying persisted state
  - Async helper: `assert_eventually/2` for polling conditions

### Fixed

- `mix durable_object.gen.migration` now correctly detects version parameters in existing migrations parsed by Sourceror/Igniter

## [0.2.0] - 2026-01-30

### Upgrading from 0.1.x

If you use the polling scheduler (`DurableObject.Scheduler.Polling`), the following changes are required. Users of the Oban scheduler are unaffected.

**Required migration:** Generate and run an upgrade migration before deploying:

```bash
mix durable_object.gen.migration
mix ecto.migrate
```

The task automatically detects your current migration version and generates the appropriate upgrade migration.

**Idempotent handlers:** The polling scheduler now uses at-least-once delivery. If a node crashes mid-handler, the alarm will be retried after `claim_ttl` expires (default: 60 seconds). Ensure your `handle_alarm/3` callbacks are idempotent.

### Added

- `mix durable_object.gen.migration` task to generate upgrade migrations automatically
- `base` option for `DurableObject.Migration.up/1` and `down/1` to support incremental upgrades
- Crash recovery for polling scheduler alarms: if the server crashes or restarts while executing an alarm handler, the alarm is automatically retried
- New `claim_ttl` option for polling scheduler (default: 60 seconds) - controls how long before a claimed alarm becomes eligible for retry. Lower values reduce recovery latency but increase risk of duplicate delivery if handlers are slow.
- Migration version 3 adds `claimed_at` column to `durable_object_alarms` table

### Changed

- Polling scheduler now uses at-least-once semantics (handlers should be idempotent)
- Alarms are claimed before firing and only deleted on success
- Failed or interrupted alarm handlers will retry after the claim TTL expires

## [0.1.5] - 2026-01-28

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

[Unreleased]: https://github.com/ChristianAlexander/durable_object/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/ChristianAlexander/durable_object/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ChristianAlexander/durable_object/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ChristianAlexander/durable_object/releases/tag/v0.1.0
