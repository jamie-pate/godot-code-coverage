# Instrumentation Contract v1.4

<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

*(Godot 4.x CLI Code Coverage Tool – Pure Source Instrumentor)*

**Status**: Fully Implementation-Locked
**Contract Version**: `1.4`
**Date**: 2026-10-11
**Changes from v1.2**: Golden-test artifact structure only (§13): one directory per corpus entry, and an optional `config.json` artifact for per-entry configuration overrides. No change to classification, mapping, metadata meaning, or error semantics. See §14.1.
**Changes from v1.1 (in v1.2)**: Resolved remaining ambiguities in disabled-instrumentation behaviour, template validation ordering, and `{path}` substitution safety.

---

### 1. Purpose

This document defines the deterministic interface and behavioral guarantees of the pure GDScript source instrumentor.

The instrumentor is a pure function that accepts:

```text
(original_source, script_path, configuration)
```

and returns either a successful `InstrumentationResult` **or** a separate `InstrumentationError`.

It must have **no dependency** on:

- `SceneTree`
- Autoloads
- Test runners (GUT, GdUnit4, etc.)
- Runtime coverage state
- Any Coverage singleton

**Core principle (fail-closed)**:

The instrumentor must never claim coverage correctness when it cannot prove that the transformation is safe and semantically equivalent. When in doubt, it must fail explicitly rather than produce plausible but incorrect coverage.

> **Scope note**: The "no SceneTree / runtime dependency" constraint applies only to the instrumentor itself. The runtime verification harness (and any corpus entries that exercise loading behaviour) are allowed to use the full Godot runtime.

---

### 2. Input Contract

```gdscript
class_name InstrumentationRequest
extends RefCounted

var source: String                    # Complete original GDScript source
var script_path: String               # Stable identifier (used in metadata & LCOV)
var config: InstrumentationConfig     # Explicit transformation configuration
```

| Field         | Requirement                                      |
|---------------|--------------------------------------------------|
| `source`      | Complete, unmodified original GDScript source    |
| `script_path` | Stable path used as the canonical identity       |
| `config`      | Explicit configuration (see §3)                  |

Identical inputs must always produce identical outputs (see §9).

---

### 3. Configuration

```gdscript
class_name InstrumentationConfig
extends RefCounted

var enable_instrumentation: bool = true
var include_non_executable: bool = false
var emit_function_metadata: bool = true
var hit_recorder_expression: String
```

#### 3.1 `enable_instrumentation = false`

When `enable_instrumentation` is `false` the instrumentor **must** return a successful `InstrumentationResult` containing:

- `instrumented_source` identical to the original `source`
- Complete `line_mappings` for every original line, each with `hit_record_inserted = false`
- `executable_lines` containing every line classified as `executable` (still reported, even though no recorder was inserted)
- `skipped_lines` containing every intentionally non-instrumented line (`non_executable` + `structural`)

This choice is mandatory so that golden-test artifacts have a single concrete expected value.

#### 3.2 `include_non_executable`

Controls whether lines classified as `non_executable` appear in the `line_mappings` array.

- `true` → every original line appears in `line_mappings`
- `false` → only `executable` and `structural` lines appear in `line_mappings`

`skipped_lines` is **always** complete and contains every intentionally non-instrumented line, regardless of this flag.

#### 3.3 `hit_recorder_expression`

This is a **template string** that the instrumentor substitutes before insertion. Supported placeholders (case-sensitive):

| Placeholder | Replaced with                          |
|-------------|----------------------------------------|
| `{line}`    | Original 1-based line number (integer) |
| `{path}`    | The `script_path` value (string)       |

Example values:

```text
__coverage_hit({line})
CoverageCollector.record("{path}", {line})
```

**Validation rules**

- The template is always validated, even when `enable_instrumentation = false`.
- An empty template or a template containing unknown placeholders produces `INVALID_CONFIGURATION`.
- Substitution is simple textual replacement with **no escaping**.
- If a pathological `script_path` (containing quotes, newlines, etc.) produces syntactically invalid GDScript after substitution, that is the caller's responsibility. The instrumentor does not attempt to escape or sanitise `{path}`.

---

### 4. Per-Line Classification

Every original source line receives **exactly one** of the following classifications:

| Classification   | Meaning                                                                                                 |
|------------------|---------------------------------------------------------------------------------------------------------|
| `executable`     | Represents independently executable GDScript behaviour that can legitimately receive a line-hit record. |
| `non_executable` | Does not represent independently executable behaviour.                                                  |
| `structural`     | Required for syntactic structure but is not itself an independently coverable statement.                |

> `structural` does **not** mean "uncovered". It means the line itself is not assigned a normal line-hit obligation.

---

### 5. Transformation Rule

For every `executable` line selected for instrumentation:

```text
original executable statement
        ↓
hit recorder insertion
        ↓
original executable statement
```

The inserted recorder **must**:

1. Execute whenever the corresponding original statement executes.
2. Preserve the statement's semantics completely.
3. Preserve surrounding indentation and block structure.
4. Introduce no observable changes to user code other than coverage collection.
5. Identify the **original** source line number (via the substituted `{line}` placeholder).

The transformer must **never** instrument comments, blank lines, purely structural lines, the coverage implementation itself, or explicitly excluded regions.

---

### 6. Line Mapping

Coverage coordinates are always expressed in **original source line numbers**.

```gdscript
class_name LineMapping
extends RefCounted

var original_line: int                # 1-based original line number
var instrumented_lines: Array[int]    # 1-based lines in the transformed source
var classification: String            # "executable" | "non_executable" | "structural"
var hit_record_inserted: bool
```

Primary mapping direction:

```text
original line → zero or more instrumented lines
```

#### 6.1 Line-number translation for runtime errors / stack traces

The instrumentor is **not** required to provide any mapping that would allow Godot runtime error messages or stack traces (which report line numbers from the *instrumented* source) to be translated back to original line numbers.

Preserving "error / exception behaviour" (§11) refers to semantic behaviour only. Line-number translation for diagnostics is explicitly out of scope for this contract.

---

### 7. Success Result

```gdscript
class_name InstrumentationResult
extends RefCounted

var contract_version: String = "1.2"
var script_path: String
var original_source: String
var instrumented_source: String
var line_mappings: Array[LineMapping]
var executable_lines: Array[int]      # Original line numbers classified as executable
var skipped_lines: Array[int]         # Intentionally non-instrumented lines only
var functions: Array[FunctionMetadata] # Optional
```

```gdscript
class_name FunctionMetadata
extends RefCounted

var name: String
var start_line: int
var end_line: int
var class_scope: String               # Empty for top-level
var is_static: bool
```

**`skipped_lines` semantics**
Contains **only** lines that were intentionally not instrumented.
An error result **must never** be represented as a successful result containing skipped lines.

---

### 8. Error Result

Failures return a separate error object. A failed transformation never exposes a usable `instrumented_source`.

```gdscript
class_name InstrumentationError
extends RefCounted

var status: InstrumentationStatus
var script_path: String
var original_line: int = -1           # -1 when not applicable
var reason: String
```

```gdscript
enum InstrumentationStatus {
    UNSUPPORTED_SYNTAX,
    INVALID_SOURCE,
    INVALID_CONFIGURATION
}
```

---

### 9. Determinism Requirements

Given identical `source`, `script_path` and `configuration`, the instrumentor must produce byte-for-byte identical `instrumented_source` and metadata.

It must not depend on execution order, SceneTree state, filesystem enumeration order, timestamps, random values, or runtime coverage state.

#### 9.1 Line endings

The instrumentor treats the source as a sequence of lines split on `\n`. A trailing `\r` (CRLF) is stripped from each line before classification and is **not** re-inserted into the instrumented source. The instrumented source is always emitted with Unix line endings (`\n` only). This rule is mandatory for determinism of golden files.

---

### 10. Error vs Skip Semantics

| Concept   | Meaning                                                                                                                                         |
|-----------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| **Skip**  | The construct is understood and intentionally receives no hit recorder. Represented in `skipped_lines`.                                         |
| **Error** | The instrumentor cannot prove that transformation is safe/correct. Returns `InstrumentationError`; no usable `instrumented_source` is produced. |

---

### 11. Semantic Preservation Guarantees

The instrumentor must preserve:

- Control-flow behaviour
- Return values
- Error / exception behaviour (semantic, not stack-trace line numbers — see §6.1)
- Variable scope and lifetime
- Evaluation order
- Static initialisation behaviour
- Lambda behaviour
- Signal connections and emission behaviour
- Coroutine / `await` behaviour
- Indentation-sensitive block structure

Textual similarity is not required; semantic equivalence for supported constructs is required.

---

### 12. Runtime Verification Pipelines

#### 12.1 Success pipeline (default)

```text
original source
      ↓
instrument → must return InstrumentationResult
      ↓
load instrumented script
      ↓
execute known paths
      ↓
collect hits
      ↓
compare against expected executable lines / hit counts
```

#### 12.2 Expected-failure pipeline

```text
original source
      ↓
instrument → must return InstrumentationError
      ↓
assert status, original_line and reason match expectations
      ↓
done
```

---

### 13. Golden-Test Artifacts

Every corpus entry lives in its own directory. The artifact names below are fixed, so each entry's artifacts sit side by side in that directory without colliding with any other entry's:

```text
tests/corpus/
  README.md
  <entry>/
    source.gd                  # all entries
    config.json                # only if the entry overrides corpus defaults
    expected.instrumented.gd   # success entries
    expected.metadata.json     # success entries
    expected_hits.json         # success entries
    expected.error.json        # expected-failure entries
```

- **Directory name**: the Seed Corpus Specification's source filename without `.gd` (e.g. `basic_statements/` for `basic_statements.gd`).
- **`.uid` sidecar**: `source.gd` keeps its Godot `.uid` sidecar beside it (`source.gd.uid`).
- **Exercise mechanism**: whether success entries carry an `exercise.gd` (§13.1) or are exercised by the GUT integration suite is decided by the runtime Hit Collector design task (#23). This layout accommodates either.

#### 13.1 Success entries

| Artifact                   | Purpose                                                       |
|----------------------------|---------------------------------------------------------------|
| `source.gd`                | Original source                                               |
| `config.json`              | *(optional)* Configuration overrides; see §13.3               |
| `expected.instrumented.gd` | Deterministic golden instrumented source                      |
| `expected.metadata.json`   | Classification, mappings, executable lines, skipped lines     |
| `expected_hits.json`       | Runtime hit expectations                                      |
| `exercise.gd`              | Script that exercises the known paths                         |

#### 13.2 Expected-failure entries

| Artifact              | Purpose                                                     |
|-----------------------|-------------------------------------------------------------|
| `source.gd`           | Original source                                             |
| `config.json`         | *(optional)* Configuration overrides; see §13.3             |
| `expected.error.json` | Expected `InstrumentationStatus`, `original_line`, `reason` |

#### 13.3 `config.json`

**Baseline.** The baseline for every `config.json` is the Seed Corpus Specification's default configuration, not the Contract §3 defaults. A `config.json` contains only the keys the entry overrides. An absent `config.json` means the corpus defaults apply unchanged.

The corpus defaults differ from the Contract §3 defaults in two fields:

| Field                     | Contract §3 default                                      | Seed Corpus Spec default     |
|---------------------------|----------------------------------------------------------|------------------------------|
| `enable_instrumentation`  | `true`                                                   | `true`                       |
| `include_non_executable`  | `false`                                                  | **`true`**                   |
| `emit_function_metadata`  | `true`                                                   | `true`                       |
| `hit_recorder_expression` | *(none, which is `INVALID_CONFIGURATION` if left empty)* | **`__coverage_hit({line})`** |

**Allowed keys.** Exactly the `InstrumentationConfig` fields of the current published contract (§3). An unknown key is an error, so a typo cannot silently fall back to a default.

**Format.** A flat JSON object with LF line endings. Example, for `disabled_instrumentation/`:

```json
{
  "enable_instrumentation": false
}
```

---

### 14. Versioning

- Document version: **1.4**
- Every successful `InstrumentationResult` exposes `contract_version = "1.4"`.
- Any change to classification, mapping, metadata meaning, unsupported-syntax behaviour, or instrumentation guarantees requires a new contract version.
- Any change to golden-test artifact structure (§13) also requires a new contract version.

#### 14.1 Version notes

**v1.4** — golden-test artifact structure only:

- §13: one directory per corpus entry, with fixed artifact names inside it.
- §13.1, §13.2: `config.json` added as an optional artifact.
- §13.3: `config.json` rules, with the Seed Corpus Specification's default configuration as the baseline.

v1.4 makes **no change** to classification, mapping, metadata meaning, or error semantics. An instrumentor that satisfies v1.2 satisfies v1.4 once it reports `contract_version = "1.4"`.

---

### 15. Fail-Closed Principle

**The instrumentor must never claim coverage correctness when it cannot prove safe transformation.**

This principle is non-negotiable.

---

**End of Instrumentation Contract v1.4**

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
