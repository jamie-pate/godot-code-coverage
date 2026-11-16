# Seed Corpus

This directory is the instrumentor's acceptance test suite: the 12 required
entries of the
[Seed Corpus Specification](../../docs/seed-corpus-specification-v1.5.md),
with the golden artifacts each one must reproduce under the
[Instrumentation Contract](../../docs/instrumentation-contract-v1.4.md)
(§12, §13).

> **Do not edit, reformat or re-save any file in this directory** unless the
> Seed Corpus Specification changes with it. Every golden line number depends
> on the exact bytes of its source. A single added blank line silently
> invalidates every golden of that entry. This has already happened once
> (#38).

## Layout

One directory per entry. The directory name is the spec's source file name
without `.gd`:

```text
tests/corpus/
  README.md                    # this file
  <entry>/
    source.gd                  # all entries
    source.gd.uid              # all entries (Godot sidecar, committed)
    config.json                # only if the entry overrides corpus defaults
    expected.metadata.json     # success entries
    expected.instrumented.gd   # success entries
    expected_hits.json         # success entries
    expected.error.json        # expected-failure entries
```

| Entry                             | Pipeline           | `config.json`   |
|-----------------------------------|--------------------|-----------------|
| `basic_statements`                | Success            | none            |
| `control_flow`                    | Success            | none            |
| `multiline`                       | Success            | none            |
| `lambdas`                         | Success            | none            |
| `static_init`                     | Success            | none            |
| `typed_annotations`               | Success            | none            |
| `class_level`                     | Success            | none            |
| `autoload_style`                  | Success            | none            |
| `await_coroutines`                | Success            | none            |
| `disabled_instrumentation`        | Success            | yes             |
| `edge_cases_unsupported_syntax`   | Expected-failure   | none            |
| `edge_cases_invalid_config`       | Expected-failure   | yes             |

The two `edge_cases_*` entries are Sub-cases A and B of the former
`edge_cases.gd`, split so each has its own `expected.error.json` (#37).

## Artifacts

| Artifact                     | Carried by          | Content                                                                               | Status                                                   |
|------------------------------|---------------------|---------------------------------------------------------------------------------------|----------------------------------------------------------|
| `source.gd`                  | every entry         | The spec's literal source block, byte for byte                                        | All 12 entries                                           |
| `config.json`                | 2 entries           | Configuration overrides only (see below)                                              | Both entries                                             |
| `expected.metadata.json`     | success entries     | `contract_version`, `line_mappings`, `executable_lines`, `skipped_lines`, `functions` | All 10 success entries (#4)                              |
| `expected.instrumented.gd`   | success entries     | Exact instrumented source                                                             | `disabled_instrumentation` only (#6); the other 9 in #28 |
| `expected_hits.json`         | success entries     | Runtime hit expectations                                                              | All 10 in #29, once #23 defines the schema               |
| `expected.error.json`        | failure entries     | `status`, `original_line`, `reason` (Contract §8, §13.2)                              | Both failure entries (#5)                                |

Notes on individual artifacts:

- **`expected.metadata.json`** leaves out `instrumented_lines`. That is fixed
  by `expected.instrumented.gd` instead (decided on #4).
- **`expected.instrumented.gd` for `disabled_instrumentation`** is an exact
  copy of its `source.gd`. With `enable_instrumentation = false`, Contract
  §3.1 requires the instrumented source to equal the original.
- **`expected.error.json`** has `original_line: -1` when no line applies
  (Contract §8). `edge_cases_invalid_config` fails on its configuration
  before any line is read, so its value is `-1`. The two `reason` strings are
  pinned exactly, because the expected-failure pipeline compares them
  (Contract §12.2). Configuration validation (#9) must produce Sub-case B's
  string exactly.

| Entry                             | `status`                  | `original_line`   | `reason`                                                    | Pinned in   |
|-----------------------------------|---------------------------|-------------------|-------------------------------------------------------------|-------------|
| `edge_cases_unsupported_syntax`   | `UNSUPPORTED_SYNTAX`      | `4`               | `"bracket continuation is not supported"`                   | #13         |
| `edge_cases_invalid_config`       | `INVALID_CONFIGURATION`   | `-1`              | `"unknown placeholder {column} in hit_recorder_expression"` | #5          |

Line 4 of Sub-case A is where its unclosed bracket opens.

## `config.json`

A `config.json` holds **only** the keys the entry overrides. If there is no
`config.json`, the corpus defaults apply unchanged. Allowed keys are exactly
the `InstrumentationConfig` fields of the current contract (§3). An unknown
key is an error, so a typo can't quietly fall back to a default. The file is
a flat JSON object.

The baseline is the **corpus default configuration**, not the Contract §3
defaults. They differ in two fields:

| Field                       | Contract §3 default                       | Corpus default                 |
|-----------------------------|-------------------------------------------|--------------------------------|
| `enable_instrumentation`    | `true`                                    | `true`                         |
| `include_non_executable`    | `false`                                   | **`true`**                     |
| `emit_function_metadata`    | `true`                                    | `true`                         |
| `hit_recorder_expression`   | none (`INVALID_CONFIGURATION` if empty)   | **`__coverage_hit({line})`**   |

Only two entries override anything:

- `disabled_instrumentation/config.json`: `enable_instrumentation: false`.
- `edge_cases_invalid_config/config.json`: `hit_recorder_expression` set to
  `"__coverage_hit({column})"`, an unknown placeholder (Contract §3.3).

## Formatting rules

- **Byte-for-byte sources.** Every `source.gd` must match its source block in
  the Seed Corpus Specification exactly. `disabled_instrumentation` and
  `edge_cases_invalid_config` are byte-for-byte copies of `basic_statements`.
  `tests/unit/test_corpus_spec_sync.gd` fails on a single byte of difference,
  in either the corpus or the spec.
- **Unix line endings only.** Every `.gd` and `.json` file here uses `\n`,
  never `\r\n`. The repository's `.gitattributes` (`* text=auto eol=lf`)
  enforces this on checkout, so a Windows clone with `core.autocrlf=true`
  can't convert the files and break every byte-for-byte comparison.
- **One final newline.** Every file ends with exactly one `\n`.
- **No reformatting.** `tests/corpus` is excluded from `gdformat` and
  `gdlint` on purpose, through `.gdcheckignore`. Don't run a formatter on
  these files by hand either. The JSON goldens are checked by
  `workspace/json_lint.py`, which checks encoding, line endings and the final
  newline but never layout. `expected.metadata.json` keeps one
  `line_mappings` object per line, so it reads line by line against
  `source.gd`.

## Golden `.gd` files inside the Godot project

Instrumented goldens call `__coverage_hit(...)`, which isn't defined
anywhere. That is safe here, as verified in
[`docs/corpus-golden-gd-verification.md`](../../docs/corpus-golden-gd-verification.md)
(#38). Godot's import, the GUT suite and `check.sh` all pass with goldens
present. Godot only reports the missing function if a golden is **loaded
as a script**.

So:

- **Read goldens as text** (`FileAccess`) and compare them. Never `load()`
  or `preload()` one.
- **Don't add a `.gdignore`** to the corpus. The GUT suites `preload` the
  `source.gd` files.
- **Golden `.uid` sidecars are not committed.** Godot generates
  `expected.*.gd.uid` when it scans a golden. Nothing loads goldens, so
  nothing refers to them by UID, and `.gitignore` ignores the sidecars to
  avoid UID churn (#6). `source.gd.uid` *is* committed, because the test
  suites load the sources.

## How the corpus is tested

| Test                                       | Checks                                                               |
|--------------------------------------------|----------------------------------------------------------------------|
| `tests/unit/test_corpus_spec_sync.gd`      | Sources are byte-identical to the spec, and the entry list matches   |
| `tests/unit/test_corpus_layout.gd`         | Each entry holds exactly the artifacts its pipeline requires         |
| `tests/unit/test_corpus_metadata.gd`       | `expected.metadata.json` against the spec's line maps and contract   |
| `tests/unit/test_corpus_instrumented.gd`   | `expected.instrumented.gd` goldens                                   |
| `tests/unit/test_corpus_errors.gd`         | `expected.error.json` goldens and their pinned values                |
| `tests/unit/test_corpus_resources.gd`      | `source.gd.uid` sidecars are valid, unique and resolve               |
| `tests/unit/test_corpus.gd` and others     | The sources run and behave as the spec describes                     |

Success entries are exercised by this GUT suite (`test_corpus_runtime.gd`
and the other `test_corpus_*.gd` files), not by a per-entry `exercise.gd`.
That may change: Contract §13 leaves `exercise.gd` conditional until the
runtime Hit Collector design (#23) decides.

## Before you change anything

- **Change the spec first.** A change to a corpus source, or to a golden
  value the spec derives, starts in the Seed Corpus Specification. Contract
  §14 decides whether it also needs a new contract version. Update the
  source, then every golden of that entry, and expect the GUT suite to fail
  until all of them agree.
- **Some golden values are not final yet.** They depend on design decisions
  still open in other Epics. Check the linked issue before assuming a value
  is settled:
  - Instrumented goldens for class-level code wait on the initializer
    strategy (#17, Epic #14). Their goldens are #28.
  - The hit-count schema for `expected_hits.json` is #23 (Epic #22). Its
    goldens are #29.
  - Sub-case A's failure is explained in the spec as a lambda-dedent
    ambiguity. #13 (Epic #8) replaces that with the bracket-continuation
    refusal its `reason` already uses. If bracket continuation is ever
    supported, Sub-case A stops failing and needs a new construct.
