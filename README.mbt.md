# bobzhang/issues

SQLite-backed DAG issue tracker with a MoonBit CLI for agents and a Rabbit Tea
dashboard for humans.

## CLI

Run the CLI through Moon while developing:

```bash
moon run --target native cmd/main -- --db issues.db init
moon run --target native cmd/main -- --db issues.db add -p 5 Build tracker
moon run --target native cmd/main -- --db issues.db link -t contains 1 2
moon run --target native cmd/main -- --db issues.db focus 1
moon run --target native cmd/main -- --db issues.db next
moon run --target native cmd/main -- --db issues.db outline
moon run --target native cmd/main -- --db issues.db serve
```

Edges are typed:

- `contains` for outline/decomposition.
- `depends_on` for blocking relationships.
- `relates_to` for loose references.

`next` returns the highest-priority unfinished, unblocked leaf under the current
focus item.

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
- `/healthz` for a simple health check.

## Validation

```bash
moon test --target native
moon test --target js
moon check --target native
moon check --target js
```
