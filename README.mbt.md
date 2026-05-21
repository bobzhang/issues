# bobzhang/issues

SQLite-backed DAG issue tracker with a MoonBit CLI for agents and a Rabbit Tea
dashboard for humans.

## CLI

Run the CLI through Moon while developing:

```bash
moon run --target native cmd/main -- --db issues.db init
moon run --target native cmd/main -- --db issues.db add -p 5 --body "Track the project plan." Build tracker
moon run --target native cmd/main -- --db issues.db add Implement CLI
moon run --target native cmd/main -- --db issues.db link -t contains iss_21845b479070a3c5 iss_0e62aff88401672c
moon run --target native cmd/main -- --db issues.db focus iss_21845b479070a3c5
moon run --target native cmd/main -- --db issues.db next
moon run --target native cmd/main -- --db issues.db todos
moon run --target native cmd/main -- --db issues.db todos --ready
moon run --target native cmd/main -- --db issues.db show iss_21845b479070a3c5
moon run --target native cmd/main -- --db issues.db outline
moon run --target native cmd/main -- --db issues.db serve
```

Issue IDs are deterministic: `add` trims the title, hashes it with SHA-256, and
uses the first 16 hex characters with an `iss_` prefix. Titles are immutable;
to rename an issue, create a new issue with the new title and relink it. Re-adding
the same title returns the same ID. If the generated SHA ID already belongs to a
different title, the CLI exits with `ISSUE_TITLE_RENAME_REQUIRED` so an agent can
choose a more specific title.

Edges are typed:

- `contains` for outline/decomposition.
- `depends_on` for blocking relationships.
- `relates_to` for loose references.

`next` returns the highest-priority unfinished, unblocked leaf under the current
focus item. `todos` renders the current focus as a recursive Markdown task list
for terminal reading. Use `todos --ready`, `todos --blocked`, or `todos --all`
for flat filtered lists.

Larger-agent workflows have mutable details, notes, claims, done evidence, search,
and an append-only event log:

```bash
moon run --target native cmd/main -- --db issues.db body iss_21845b479070a3c5 "Mutable details and acceptance criteria."
moon run --target native cmd/main -- --db issues.db note iss_21845b479070a3c5 "Found the schema edge case."
moon run --target native cmd/main -- --db issues.db claim --agent codex --ttl-minutes 60 iss_21845b479070a3c5
moon run --target native cmd/main -- --db issues.db done iss_0e62aff88401672c "Validated with moon test --target native."
moon run --target native cmd/main -- --db issues.db events iss_21845b479070a3c5
moon run --target native cmd/main -- --db issues.db search schema
moon run --target native cmd/main -- --db issues.db release --agent codex iss_21845b479070a3c5
```

The SQLite schema records migrations in `schema_migrations`. Current hashed-ID
databases migrate additively, and old numeric-ID databases are migrated into
deterministic title-hash IDs with `items_legacy_numeric` backup tables.

## Dashboard

Generate a static dashboard bundle from the SQLite database:

```bash
moon run --target native cmd/main -- --db issues.db dashboard --out dashboard-dist
```

Open `dashboard-dist/index.html` in a browser. The command writes `data.js`,
builds the MoonBit/Rabbit Tea JS app, and copies it to `app.js`.

For a live local viewer backed by SQLite, run:

```bash
moon run --target native cmd/main -- --db issues.db serve --port 8080
```

Then open `http://127.0.0.1:8080`. The service exposes:

- `/` and `/index.html` for the dashboard.
- `/data.js` for the dashboard bootstrap data.
- `/api/graph` for graph JSON.
- `/api/next` for the next actionable todo as JSON.
- `/api/outline` for the text outline.
- `POST /api/body` to update mutable issue body text.
- `POST /api/status` to update mutable status; `done` requires evidence.
- `POST /api/note` to append an issue note.
- `/healthz` for a simple health check.

The live dashboard can edit body text, status, and append-only notes. Issue
titles remain immutable: the UI only displays them, and the service has no title
mutation endpoint.

## Validation

```bash
moon test --target native
moon test --target js
moon check --target native
moon check --target js
```
