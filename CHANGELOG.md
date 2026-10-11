# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
follow `shard.yml`'s own `version:` field (synced via `make version`, then
tagged via `make tag`).

## [Unreleased]

- Upgraded `ameba` dev dependency from `~> 1.6.0` to `~> 1.7.0`.
- Refreshed `crystina` and `mux` dependencies (no public API changes).
- Fixed `.ameba.yml`: the custom top-level `Excluded:` list was overriding
  ameba's built-in `lib` exclusion, causing vendored dependency sources to be
  linted; `lib` was added back to `Excluded`.
- Fixed ameba 1.7.0 violations in source: converted multi-line curly-brace
  blocks to `do`...`end` (`Style/MultilineCurlyBlock`), removed a redundant
  `else nil` branch in a `case` expression (`Lint/ElseNil`), and removed
  stale `# ameba:disable Lint/UselessAssign` comments in
  `spec/macro/exception_spec.cr` that ameba 1.7.0 no longer requires
  (`Lint/UnneededDisableDirective`). Ameba's `--fix` auto-corrected the bulk
  of other new violations (`Style/RedundantNilInControlExpression`,
  `Lint/WhitespaceAroundMacroExpression`, `Style/PercentLiteralDelimiters`,
  `Style/HeredocIndent`, `Lint/SpecEqWithBoolOrNilLiteral`,
  `Lint/Formatting`, `Style/VerboseNilType`, `Style/RedundantBegin`).
- CI: added an explicit "Build ameba" step (`shards build ameba`) between
  `shards install` and the ameba lint step, since ameba 1.7.0 no longer ships
  a `postinstall`/`executables` build hook in its `shard.yml`.
- Makefile: `lib/ameba/bin/ameba` target now also runs
  `shards build ameba`, for the same reason.
