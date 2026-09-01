# Spis Desktop

A macOS application over [`Spis`](https://github.com/wisent-ai/spis) — the evidence-grade reference corpus: browse every catalog and its measured state, read the evidence contract, and run the corpus's read-only commands from one window.

- **Browse catalogs** — all fifteen catalogs with record counts and the complete/partial split, decoded live from `example-catalogs.json`.
- **Catalog detail** — records, complete/partial, image and structure counts, the measured provenance mix, and the file paths each catalog owns.
- **Command console** — runs read-only operations: `catalogs --check`, `drift`, `verify`, and `capture --list`.
- **Manage references** — add, remove, and update reference records in catalogs.
- **Crawlers** — run crawls across all fifteen catalogs. Pick a catalog, set the target host, optionally specify a record (or crawl all) and admission URL. Operations: start a crawl, check status with per-catalog breakdown and record metrics (complete, partial, failed), resume paused runs, and import results. Diagnostics show artifact locations, record gaps, and error details.

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
