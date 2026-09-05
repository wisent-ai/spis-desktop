# Spis Desktop

A macOS application over [`Spis`](https://github.com/wisent-ai/spis) — the evidence-grade reference corpus: browse every catalog and its measured state, run the corpus's reference commands, and execute crawl operations across 15 product families using six engine types from one window.

- **Browse catalogs** — all fifteen catalogs with record counts and the complete/partial split, decoded live from `example-catalogs.json`.
- **Catalog detail** — records, complete/partial, image and structure counts, the measured provenance mix, and the file paths each catalog owns.
- **Reference commands** — read-only operations: `catalogs --check`, `drift`, `verify`, and `capture --list`.
- **Manage references** — add, remove, and update reference records in catalogs.
- **Corpus adoption** — first use and **Manage → Use an existing corpus** open a native directory picker and call Spis core's `corpus adopt` operation through the loopback API. The app does not parse or copy the corpus.
- **Crawlers** — run native crawl operations across all 15 product families using six engines (mobile, desktop, web, TUI, CLI, docs) via Rust `spis crawl start|status|resume|import` commands. Pick a product family (all 15 or individual), optionally specify a record (or crawl all), set Stado host target, and Stado-resolved Weles admission endpoint. Operations: (1) start a crawl and reattach manually by entering its run ID in "Load Existing Run" after app restart; (2) check status with per-catalog breakdown and record metrics (complete, partial, failed); (3) resume paused/failed runs; (4) import results (mutating operation that updates corpus records from crawl artifacts). Diagnostics: preflight checks per catalog (schema, engine, host, Weles connectivity, no-permission-prompts flag), per-record readiness and permission requirements, artifact locations (artifact_uri for service references, output_uri for external data), record gaps, and error details. Crawl sessions are persisted by Spis core via their run IDs; reattach by pasting the run ID in the "Load Existing Run" field.
- **First-run walkthrough** — three screens explain the evidence boundary and finish only after Spis core validates and persists an unpacked canonical corpus and the app decodes one of its catalogs. Replay it from **Manage → First-run walkthrough → Show it again**.

## Build and run

```bash
swift build
.build/debug/ReferenceEngine
```

The app locates a `spis` binary in standard search paths or repository checkouts (e.g., `target/release/spis`), or you can pin one explicitly:

```bash
REFERENCE_ENGINE_ROOT=~/Documents/CodingProjects/Wisent/spis .build/debug/ReferenceEngine
```

Requires macOS 14+ and Swift 6 toolchain. The Rust `spis` binary must be executable and discoverable (the app searches `PATH`, repository checkouts, and `target/release/`).

The adopted corpus location is stored by Spis core at
`~/.config/spis/corpus.json` (or under `XDG_CONFIG_HOME`). The original
catalogs, reference records, provenance, screenshots, recordings, and receipts
stay in their selected directory. Repeated adoption is reported unchanged;
archive files and incomplete or escaping corpus paths are refused before the
saved location changes.

## Rules

The app provides visibility into measured catalog state and exposes both read-only reference commands and mutating crawl operations. Crawl operations invoke the Rust `spis crawl` CLI directly and update corpus records via `crawl import`. Crawl sessions are durable per Spis core: run IDs persist, and you can resume them by manually reattaching through the "Load Existing Run" field (no automatic session recovery is performed by the GUI).
