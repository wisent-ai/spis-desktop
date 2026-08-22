# Spis Desktop

A macOS application over [`Spis`](https://github.com/wisent-ai/spis) — the evidence-grade reference corpus: browse every catalog and its measured state, read the evidence contract, and run the corpus's read-only commands from one window.

## What it shows

- **Catalogs sidebar** — all fifteen catalogs with record counts and the complete/partial split, decoded live from `example-catalogs.json`.
- **Catalog detail** — records, complete/partial, image and structure counts, the measured provenance mix, and the file paths each catalog owns.
- **Command console** — runs `bin/reference catalogs --check`, `drift`, `verify` (dry), and `capture --list` against the checkout, showing output and exit code. Read-only by construction; nothing in this app mutates records.

## Build and run

```bash
swift build
.build/debug/ReferenceEngine
```

The app locates a `reference-engine` checkout by walking up from its own binary, or you can pin one explicitly:

```bash
REFERENCE_ENGINE_ROOT=~/Documents/CodingProjects/Wisent/reference-engine .build/debug/ReferenceEngine
```

Requires macOS 14+ and Swift 6 toolchain. The Python CLI must be executable (`chmod +x bin/reference` inside the engine checkout).

## Rules

The app is a viewer. Every mutating stage of the pipeline stays in the CLI and the repository it serves; this surface exists so the measured state of the corpus is visible without opening a terminal.
