---
defaults:
  timeout: 30s
---

# Issue Tracker CLI Contract

This document is both executable documentation and a black-box regression test
for the SQLite-backed issue tracker. Scrut runs each `scrut` block against the
compiled CLI, with a fresh temporary database for the whole document.

## Setup

Build the native CLI once, create the temporary database path, and define a
small `issues` shell function used by the rest of the document.

```scrut {timeout: 90s}
$ source "$TESTDIR"/setup.sh
```

## Initialize Storage

The database starts empty and is created or migrated by `init`.

```scrut
$ issues init
initialized *issues.db (glob)
```

## Create Deterministic Issues

Issue IDs are SHA-derived from immutable titles. The same title always maps to
the same `iss_` ID, which keeps independent branches from racing on a numeric
counter.

```scrut
$ export ROOT=$(issues add -p 5 --body "Track the project plan." Build tracker)
> echo "$ROOT"
iss_21845b479070a3c5
```

```scrut
$ export CLI=$(issues add -p 8 Implement CLI)
> echo "$CLI"
iss_0e62aff88401672c
```

```scrut
$ export DASHBOARD=$(issues add -p 6 Implement dashboard)
> echo "$DASHBOARD"
iss_e90472e505d49bef
```

```scrut
$ export DOCS=$(issues add -p 3 Prepare docs)
> echo "$DOCS"
iss_8ec5a2d8168fe4c2
```

Re-adding the same title returns the same deterministic ID.

```scrut
$ issues add Build tracker
iss_21845b479070a3c5
```

The title itself is immutable. This direct SQLite update is expected to fail
because the schema trigger rejects renames.

```scrut
$ sqlite3 "$ISSUES_DB" "UPDATE items SET title='Renamed tracker' WHERE id='$ROOT';"
[19]
```

## Model Work as a Typed DAG

`contains` edges form the outline, while `depends_on` edges block work.

```scrut
$ issues link -t contains "$ROOT" "$CLI"
linked iss_21845b479070a3c5 -[contains]-> iss_0e62aff88401672c
```

```scrut
$ issues link -t contains "$ROOT" "$DASHBOARD"
linked iss_21845b479070a3c5 -[contains]-> iss_e90472e505d49bef
```

```scrut
$ issues link -t contains "$ROOT" "$DOCS"
linked iss_21845b479070a3c5 -[contains]-> iss_8ec5a2d8168fe4c2
```

```scrut
$ issues link -t depends_on "$DASHBOARD" "$CLI"
linked iss_e90472e505d49bef -[depends_on]-> iss_0e62aff88401672c
```

The current focus scopes recursive queries.

```scrut
$ issues focus "$ROOT"
current iss_21845b479070a3c5
```

## Query the Next Agent Task

The next item is the highest-priority unfinished leaf that is not blocked.

```scrut
$ issues next
#iss_0e62aff88401672c Implement CLI [todo p8]
```

## Render Terminal Todos

The default todo view is a recursive Markdown checklist under the current focus.

```scrut
$ issues todos | sed '/^$/d'
- [ ] #iss_21845b479070a3c5 Build tracker (p5 current)
  - [ ] #iss_0e62aff88401672c Implement CLI (p8)
  - [ ] #iss_e90472e505d49bef Implement dashboard (p6 blocked)
  - [ ] #iss_8ec5a2d8168fe4c2 Prepare docs (p3)
```

Flat ready and blocked views are useful for agents that need a filtered queue.

```scrut
$ issues todos --ready | sed '/^$/d'
- [ ] #iss_0e62aff88401672c Implement CLI (p8)
- [ ] #iss_8ec5a2d8168fe4c2 Prepare docs (p3)
```

```scrut
$ issues todos --blocked | sed '/^$/d'
- [ ] #iss_e90472e505d49bef Implement dashboard (p6 blocked)
```

The outline view keeps status text instead of Markdown checkboxes.

```scrut
$ issues outline | sed '/^$/d'
- [todo] #iss_21845b479070a3c5 Build tracker (p5 current)
  - [todo] #iss_0e62aff88401672c Implement CLI (p8)
  - [todo] #iss_e90472e505d49bef Implement dashboard (p6 blocked)
  - [todo] #iss_8ec5a2d8168fe4c2 Prepare docs (p3)
```

## Import Todos From Markdown

Markdown task lists can be imported in batch. The parser uses CommonMark task
list rules; nested task bullets are indented to the parent item's content
column.

```scrut
$ cat > "$TMPDIR"/markdown-plan.md <<'EOF'
> - [ ] Batch root
>       - [x] Batch child done
>       - [ ] Batch child open
> EOF
> issues import-markdown "$TMPDIR"/markdown-plan.md | sed '/^$/d'
imported 3 todos
- #iss_* Batch root [todo] (glob)
  - #iss_* Batch child done [done] (glob)
  - #iss_* Batch child open [todo] (glob)
```

## Mutate Details Without Renaming

The title is stable, but the body, notes, and status are intentionally mutable.

```scrut
$ issues body "$ROOT" "Mutable details and acceptance criteria."
updated #iss_21845b479070a3c5 body
```

```scrut
$ issues show "$ROOT" | sed -n '1,7p'
#iss_21845b479070a3c5 Build tracker
Status: todo
Priority: 5
Claim: none

Body:
  Mutable details and acceptance criteria.
```

```scrut
$ issues note "$ROOT" "Found the schema edge case."
noted #iss_21845b479070a3c5
```

Notes and event bodies are searchable.

```scrut
$ issues search schema | sed '/^$/d'
#iss_21845b479070a3c5 Build tracker [todo p5]
```

Claims provide a simple lease for agent coordination.

```scrut
$ issues claim --agent codex --ttl-minutes 60 "$CLI"
claimed #iss_0e62aff88401672c by codex
```

```scrut
$ issues release --agent codex "$CLI"
released #iss_0e62aff88401672c
```

## Complete Work With Evidence

`done` requires evidence and unblocks dependents.

```scrut
$ issues done "$CLI" "Validated with scrut."
#iss_0e62aff88401672c done
```

```scrut
$ issues todos --ready | sed '/^$/d'
- [ ] #iss_e90472e505d49bef Implement dashboard (p6)
- [ ] #iss_8ec5a2d8168fe4c2 Prepare docs (p3)
```

The completed item now renders as checked when viewing all scoped items.

```scrut
$ issues todos --all | grep 'Implement CLI'
- [x] #iss_0e62aff88401672c Implement CLI (p8)
```
