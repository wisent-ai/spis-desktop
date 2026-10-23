# Spis Desktop

A macOS application over [`Spis`](https://github.com/wisent-ai/spis) — the evidence-grade reference corpus: browse every catalog and its measured state, run the corpus's reference commands, and execute crawl operations across 15 product families using six engine types from one window.

- **Browse catalogs** — all fifteen catalogs with record counts and the complete/partial split, decoded live from `example-catalogs.json`.
- **Catalog detail** — records, complete/partial, image and structure counts, the measured provenance mix, and the file paths each catalog owns.
- **Reference commands** — read-only operations: `catalogs --check`, `drift`, `verify`, and `capture --list`.
- **Manage references** — add and remove records. Each record's **Edit** button opens metadata changes for source URL, category, selection note and owner. Only filled fields change; record number, name and retained evidence stay intact. **Save changes** invokes `reference-record edit` through the loopback API; a refusal keeps the form open and displays the backend cause.
- **Manage product types** — **Manage → New product type** adds a catalog with zero records (`spis catalog-type add`); with a type selected, **Save product type** changes its title, description or slug and **Remove product type** deletes it (`catalog-type edit|remove`). Removing a type that holds records asks first and then passes `--force`. Every refusal shows in the outcome panel in Spis's own words.
- **Corpus adoption** — first use and **Manage → Use an existing corpus** open a native directory picker and call Spis core's `corpus adopt` operation through the loopback API. The app does not parse or copy the corpus.
- **Crawlers** — run native crawl operations across all 15 product families using six engines (mobile, desktop, web, TUI, CLI, docs) via Rust `spis crawl start|status|resume|import` commands. Pick a product family (all 15 or individual), optionally specify a record (or crawl all), set Stado host target, and Stado-resolved Weles admission endpoint. Operations: (1) start a crawl and reattach manually by entering its run ID in "Load Existing Run" after app restart; (2) check status with per-catalog breakdown and record metrics (complete, partial, failed); (3) resume paused/failed runs; (4) import results (mutating operation that updates corpus records from crawl artifacts). Diagnostics: preflight checks per catalog (schema, engine, host, Weles connectivity, no-permission-prompts flag), per-record readiness and permission requirements, artifact locations (artifact_uri for service references, output_uri for external data), record gaps, and error details. Crawl sessions are persisted by Spis core via their run IDs; reattach by pasting the run ID in the "Load Existing Run" field.
- **First-run walkthrough** — three screens explain the evidence boundary and finish only after Spis core validates and persists an unpacked canonical corpus and the app decodes one of its catalogs. Replay it from **Manage → First-run walkthrough → Show it again**.

## Build and run

Spis Desktop runs the `spis` command-line core, so install that first:

```bash
stado product install spis --surface cli   # installs ~/.stado/bin/spis
```

([Stado onboarding](https://stado.wisent.com/docs/onboarding) installs `stado`.)
Then build and open the app (macOS 14+, Swift 5.10 or newer):

```bash
swift build
.build/debug/Spis
```

The app runs the first `spis` it finds, in this order: the checkout
`REFERENCE_ENGINE_ROOT` names (`target/release/spis`, else `target/debug/spis`),
a checkout above the app or its `spis` sibling, `~/.stado/bin/spis`, then
`PATH`. To run a checkout you built yourself:

```bash
REFERENCE_ENGINE_ROOT=/path/to/spis .build/debug/Spis
```

When none is found, the app names every place it looked and the install
command above.

The adopted corpus location is stored by Spis core at
`~/.config/spis/corpus.json` (or under `XDG_CONFIG_HOME`). The original
catalogs, reference records, provenance, screenshots, recordings, and receipts
stay in their selected directory. Repeated adoption is reported unchanged;
archive files and incomplete or escaping corpus paths are refused before the
saved location changes.

## Rules

The app provides visibility into measured catalog state and exposes both read-only reference commands and mutating crawl operations. Crawl operations invoke the Rust `spis crawl` CLI directly and update corpus records via `crawl import`. Crawl sessions are durable per Spis core: run IDs persist, and you can resume them by manually reattaching through the "Load Existing Run" field (no automatic session recovery is performed by the GUI).
