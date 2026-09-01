# Spis Desktop

A macOS application over [`Spis`](https://github.com/wisent-ai/spis) — the evidence-grade reference corpus: browse every catalog and its measured state, read the evidence contract, run all corpus crawler commands from one integrated surface, and manage reference records.

## What it shows

- **Browse catalogs** — all fifteen catalogs with record counts and the complete/partial split, decoded live from `example-catalogs.json`.
- **Catalog detail** — records, complete/partial, image and structure counts, the measured provenance mix, and the file paths each catalog owns.
- **Command console** — runs read-only commands: `catalogs --check`, `drift`, `verify`, and `capture --list`.
- **Crawler launcher** — runs real crawlers on selected Stado hosts with full progress tracking:
  - Mobile crawlers (iOS via Appium, Android via Appium)
  - Desktop crawlers (macOS via Cua Driver, cross-platform desktop)
  - Web crawlers (8 interface families via Weles)
  - Terminal application crawler (PTY-based)
  - CLI crawler (PTY-based command crawling)
  - Documentation crawler (HTTP-based)
- **Crawler status** — displays queued/running/pending review/completed states with record counts and artifact locations.
- **Diagnostics** — host connectivity, catalog availability, and completion rates.
- **Reference management** — add, remove, and update records; derive guidelines from captured references.

## Build and run

```bash
swift build
.build/debug/ReferenceEngine
```

The app locates a `spis` checkout by walking up from its own binary, or you can pin one explicitly:

```bash
REFERENCE_ENGINE_ROOT=~/Documents/CodingProjects/Wisent/spis .build/debug/ReferenceEngine
```

Requires macOS 14+ and Swift 6 toolchain. The Python CLI must be executable (`chmod +x bin/reference` inside the engine checkout).

## Rules

The app is a viewer. Every mutating stage of the pipeline stays in the CLI and the repository it serves; this surface exists so the measured state of the corpus is visible without opening a terminal.
