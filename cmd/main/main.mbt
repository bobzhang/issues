///|
struct ItemRow {
  id : String
  title : String
  body : String
  status : String
  priority : Int
} derive(FromJson)

///|
struct LegacyItemRow {
  id : Int
  title : String
  status : String
  priority : Int
} derive(FromJson)

///|
struct EdgeRow {
  from_id : String
  to_id : String
  kind : String
} derive(FromJson)

///|
struct LegacyEdgeRow {
  from_id : Int
  to_id : Int
  kind : String
} derive(FromJson)

///|
struct ExistingItemRow {
  id : String
  title : String
} derive(FromJson)

///|
struct ColumnRow {
  name : String
} derive(FromJson)

///|
struct NoteRow {
  note_id : Int
  body : String
  created_at : String
} derive(FromJson)

///|
struct EventRow {
  event_id : Int
  item_id : String
  event_type : String
  agent : String
  body : String
  created_at : String
} derive(FromJson)

///|
struct ClaimRow {
  item_id : String
  agent : String
  claimed_at : String
  lease_until : String
} derive(FromJson)

///|
struct StateRow {
  value : String
} derive(FromJson)

///|
struct BodyPayload {
  id : String
  body : String
} derive(FromJson)

///|
struct NotePayload {
  id : String
  body : String
} derive(FromJson)

///|
struct StatusPayload {
  id : String
  status : String
  evidence : String
} derive(FromJson)

///|
struct MarkdownTodo {
  title : String
  status : @issues.Status
  children : Array[MarkdownTodo]
} derive(Debug)

///|
async fn main {
  let command = cli_command()
  let matches = command.parse(env=@env.get_env_vars())
  guard matches.subcommand is Some((name, sub)) else {
    println(command.render_help())
    return
  }
  let db = get_one(sub, "db").unwrap_or("issues.db")
  match name {
    "init" => {
      init_db(db)
      println("initialized \{db}")
    }
    "add" => {
      let title = get_many(sub, "title").join(" ")
      let status = @issues.Status::from_storage(
        get_one(sub, "status").unwrap_or("todo"),
      )
      let priority : Int = @strconv.from_str(
        get_one(sub, "priority").unwrap_or("0"),
      )
      let body = get_one(sub, "body").unwrap_or("")
      let id = add_item(db, title, body, status, priority)
      println(id)
    }
    "link" => {
      let from_id = require_one(sub, "from")
      let to_id = require_one(sub, "to")
      let kind = @issues.EdgeKind::from_storage(
        get_one(sub, "type").unwrap_or("contains"),
      )
      add_edge(db, from_id, to_id, kind)
      println("linked \{from_id} -[\{kind.to_storage()}]-> \{to_id}")
    }
    "focus" => {
      let id = require_one(sub, "item")
      set_focus(db, id)
      println("current \{id}")
    }
    "current" => {
      let graph = load_graph(db)
      match graph.current_id {
        Some(id) => println(id)
        None => println("")
      }
    }
    "next" => {
      let focus = get_one(sub, "item")
      let graph = load_graph(db)
      match graph.next_todo(focus) {
        Some(item) =>
          println(
            "#\{item.id} \{item.title} [\{item.status.to_storage()} p\{item.priority}]",
          )
        None => println("no actionable todo")
      }
    }
    "outline" => {
      let focus = get_one(sub, "item")
      println(load_graph(db).outline(focus))
    }
    "todos" => {
      let focus = get_one(sub, "item")
      let graph = load_graph(db)
      if get_flag(sub, "ready") {
        println(graph.ready_todos_markdown(focus))
      } else if get_flag(sub, "blocked") {
        println(graph.blocked_todos_markdown(focus))
      } else if get_flag(sub, "all") {
        println(graph.all_todos_markdown(focus))
      } else {
        println(graph.todos_markdown(focus))
      }
    }
    "show" => {
      let id = require_one(sub, "item")
      println(show_item(db, id))
    }
    "body" => {
      let id = require_one(sub, "item")
      let body = get_many(sub, "body").join(" ")
      set_body(db, id, body)
      println("updated #\{id} body")
    }
    "note" => {
      let id = require_one(sub, "item")
      let body = get_many(sub, "note").join(" ")
      add_note(db, id, body)
      println("noted #\{id}")
    }
    "claim" => {
      let id = require_one(sub, "item")
      let agent = require_one(sub, "agent")
      let ttl_minutes : Int = @strconv.from_str(
        get_one(sub, "ttl-minutes").unwrap_or("0"),
      )
      claim_item(db, id, agent, ttl_minutes)
      println("claimed #\{id} by \{agent}")
    }
    "release" => {
      let id = require_one(sub, "item")
      let agent = get_one(sub, "agent").unwrap_or("")
      release_item(db, id, agent)
      println("released #\{id}")
    }
    "done" => {
      let id = require_one(sub, "item")
      let evidence = get_many(sub, "evidence").join(" ")
      set_status(db, id, Done, Some(evidence))
      println("#\{id} done")
    }
    "status" => {
      let id = require_one(sub, "item")
      let status = @issues.Status::from_storage(require_one(sub, "status"))
      set_status(db, id, status, get_one(sub, "evidence"))
      println("#\{id} \{status.to_storage()}")
    }
    "events" => {
      let id = get_one(sub, "item")
      let limit : Int = @strconv.from_str(get_one(sub, "limit").unwrap_or("20"))
      println(events_view(db, id, limit))
    }
    "search" => {
      let query = get_many(sub, "query").join(" ")
      println(search_view(db, query))
    }
    "import-markdown" => {
      let path = require_one(sub, "file")
      let parent_id = get_one(sub, "parent")
      let source = @fs.read_file(path).text()
      let todos = markdown_todos_from_string(source)
      let report = import_markdown_todos(db, parent_id, todos)
      println(report)
    }
    "export-json" => {
      let graph = load_graph(db)
      println(graph.to_json().stringify(indent=2))
    }
    "dashboard" => {
      let out_dir = get_one(sub, "out").unwrap_or("dashboard-dist")
      write_dashboard_files(db, out_dir)
      println("wrote \{out_dir}")
    }
    "serve" => {
      let host = get_one(sub, "host").unwrap_or("127.0.0.1")
      let port : Int = @strconv.from_str(get_one(sub, "port").unwrap_or("8080"))
      println("serving http://\{host}:\{port}")
      serve_dashboard(db, host, port)
    }
    other => cli_fail("unhandled subcommand: \{other}")
  }
}

///|
fn cli_command() -> @argparse.Command {
  let item_arg = @argparse.PositionArg(
    "item",
    num_args=@argparse.ValueRange::single(),
  )
  let optional_item_arg = @argparse.PositionArg(
    "item",
    num_args=@argparse.ValueRange(lower=0, upper=1),
  )
  @argparse.Command(
    "issues",
    about="SQLite-backed DAG issue tracker for agents and humans.",
    version="0.1.5",
    subcommand_required=true,
    options=[
      @argparse.OptionArg(
        "db",
        long="db",
        env="ISSUES_DB",
        default_values=["issues.db"],
        global=true,
        about="SQLite database path.",
      ),
    ],
    subcommands=[
      @argparse.Command("init", about="Create or migrate the SQLite schema."),
      @argparse.Command(
        "add",
        about="Add an issue item and print its id.",
        options=[
          @argparse.OptionArg(
            "body",
            long="body",
            about="Initial mutable issue body/details.",
          ),
          @argparse.OptionArg("status", long="status", default_values=["todo"]),
          @argparse.OptionArg("priority", long="priority", short='p', default_values=[
            "0",
          ]),
        ],
        positionals=[
          @argparse.PositionArg("title", num_args=@argparse.ValueRange(lower=1)),
        ],
      ),
      @argparse.Command(
        "link",
        about="Add a typed edge: contains, depends_on, or relates_to.",
        options=[
          @argparse.OptionArg("type", long="type", short='t', default_values=[
            "contains",
          ]),
        ],
        positionals=[
          @argparse.PositionArg("from", num_args=@argparse.ValueRange::single()),
          @argparse.PositionArg("to", num_args=@argparse.ValueRange::single()),
        ],
      ),
      @argparse.Command("focus", about="Set the current focus item.", positionals=[
        item_arg,
      ]),
      @argparse.Command("current", about="Print the current focus item id."),
      @argparse.Command(
        "next",
        about="Print the next actionable todo under the focus item.",
        positionals=[optional_item_arg],
      ),
      @argparse.Command(
        "outline",
        about="Print a human-readable contains outline.",
        positionals=[optional_item_arg],
      ),
      @argparse.Command(
        "todos",
        about="Print a Markdown task list under the focus item.",
        flags=[
          @argparse.FlagArg("ready", long="ready", conflicts_with=[
            "blocked", "all",
          ]),
          @argparse.FlagArg("blocked", long="blocked", conflicts_with=[
            "ready", "all",
          ]),
          @argparse.FlagArg("all", long="all", conflicts_with=[
            "ready", "blocked",
          ]),
        ],
        positionals=[optional_item_arg],
      ),
      @argparse.Command(
        "show",
        about="Show one issue with details, relations, claim, notes, and events.",
        positionals=[item_arg],
      ),
      @argparse.Command("body", about="Set mutable issue body/details.", positionals=[
        item_arg,
        @argparse.PositionArg(
          "body",
          num_args=@argparse.ValueRange(lower=1),
          allow_hyphen_values=true,
        ),
      ]),
      @argparse.Command("note", about="Append a note to an issue.", positionals=[
        item_arg,
        @argparse.PositionArg(
          "note",
          num_args=@argparse.ValueRange(lower=1),
          allow_hyphen_values=true,
        ),
      ]),
      @argparse.Command(
        "claim",
        about="Claim an issue for an agent, optionally with a lease.",
        options=[
          @argparse.OptionArg("agent", long="agent", required=true),
          @argparse.OptionArg("ttl-minutes", long="ttl-minutes", default_values=[
            "0",
          ]),
        ],
        positionals=[item_arg],
      ),
      @argparse.Command(
        "release",
        about="Release an issue claim.",
        options=[@argparse.OptionArg("agent", long="agent")],
        positionals=[item_arg],
      ),
      @argparse.Command(
        "done",
        about="Mark an issue done with required evidence.",
        positionals=[
          item_arg,
          @argparse.PositionArg(
            "evidence",
            num_args=@argparse.ValueRange(lower=1),
            allow_hyphen_values=true,
          ),
        ],
      ),
      @argparse.Command(
        "status",
        about="Set item status: todo, in-progress, or done.",
        options=[@argparse.OptionArg("evidence", long="evidence")],
        positionals=[
          item_arg,
          @argparse.PositionArg(
            "status",
            num_args=@argparse.ValueRange::single(),
          ),
        ],
      ),
      @argparse.Command(
        "events",
        about="Print append-only event history.",
        options=[
          @argparse.OptionArg("limit", long="limit", default_values=["20"]),
        ],
        positionals=[optional_item_arg],
      ),
      @argparse.Command(
        "search",
        about="Search issue titles, bodies, notes, and event text.",
        positionals=[
          @argparse.PositionArg("query", num_args=@argparse.ValueRange(lower=1)),
        ],
      ),
      @argparse.Command(
        "import-markdown",
        about="Create issue todos from a Markdown task list.",
        options=[@argparse.OptionArg("parent", long="parent")],
        positionals=[
          @argparse.PositionArg("file", num_args=@argparse.ValueRange::single()),
        ],
      ),
      @argparse.Command("export-json", about="Export the full graph as JSON."),
      @argparse.Command(
        "dashboard",
        about="Write static dashboard data and HTML files.",
        options=[
          @argparse.OptionArg("out", long="out", default_values=[
            "dashboard-dist",
          ]),
        ],
      ),
      @argparse.Command(
        "serve",
        about="Serve the dashboard and graph JSON from SQLite.",
        options=[
          @argparse.OptionArg("host", long="host", default_values=["127.0.0.1"]),
          @argparse.OptionArg("port", long="port", short='p', default_values=[
            "8080",
          ]),
        ],
      ),
    ],
  )
}

///|
fn get_one(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn get_many(matches : @argparse.Matches, name : String) -> Array[String] {
  match matches.values.get(name) {
    Some(values) => values
    None => []
  }
}

///|
fn get_flag(matches : @argparse.Matches, name : String) -> Bool {
  match matches.flags.get(name) {
    Some(value) => value
    None => false
  }
}

///|
fn require_one(matches : @argparse.Matches, name : String) -> String {
  match get_one(matches, name) {
    Some(value) => value
    None => cli_fail("missing argument: \{name}")
  }
}

///|
fn[A] cli_fail(message : String) -> A {
  println(message)
  @sys.exit(1)
  panic()
}

///|
async fn init_db(db : String) -> Unit {
  let current_schema = sqlite_scalar(
    db, "SELECT sql FROM sqlite_master WHERE type='table' AND name='items' LIMIT 1;",
  )
  if current_schema.contains("INTEGER PRIMARY KEY") {
    migrate_numeric_id_db(db)
  }
  ensure_schema(db)
  if !table_has_column(db, "items", "body") {
    ignore(
      sqlite_exec(
        db, "ALTER TABLE items ADD COLUMN body TEXT NOT NULL DEFAULT '';",
      ),
    )
  }
  let migrations =
    #|INSERT OR IGNORE INTO schema_migrations(version) VALUES('001_deterministic_ids');
    #|INSERT OR IGNORE INTO schema_migrations(version) VALUES('002_agent_workflow');
    #|
  ignore(sqlite_exec(db, migrations))
}

///|
async fn ensure_schema(db : String) -> Unit {
  let schema =
    #|PRAGMA foreign_keys = ON;
    #|CREATE TABLE IF NOT EXISTS schema_migrations (
    #|  version TEXT PRIMARY KEY,
    #|  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    #|);
    #|CREATE TABLE IF NOT EXISTS items (
    #|  id TEXT PRIMARY KEY,
    #|  title TEXT NOT NULL,
    #|  body TEXT NOT NULL DEFAULT '',
    #|  status TEXT NOT NULL DEFAULT 'todo',
    #|  priority INTEGER NOT NULL DEFAULT 0,
    #|  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    #|  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    #|);
    #|CREATE UNIQUE INDEX IF NOT EXISTS items_title_unique ON items(title);
    #|CREATE TRIGGER IF NOT EXISTS items_title_immutable
    #|BEFORE UPDATE OF title ON items
    #|FOR EACH ROW
    #|WHEN NEW.title <> OLD.title
    #|BEGIN
    #|  SELECT RAISE(ABORT, 'issue titles are immutable; create a new issue with a new title');
    #|END;
    #|CREATE TABLE IF NOT EXISTS edges (
    #|  from_id TEXT NOT NULL,
    #|  to_id TEXT NOT NULL,
    #|  kind TEXT NOT NULL,
    #|  UNIQUE(from_id, to_id, kind),
    #|  CHECK(kind IN ('contains', 'depends_on', 'relates_to')),
    #|  FOREIGN KEY(from_id) REFERENCES items(id) ON DELETE CASCADE,
    #|  FOREIGN KEY(to_id) REFERENCES items(id) ON DELETE CASCADE
    #|);
    #|CREATE TABLE IF NOT EXISTS state (
    #|  key TEXT PRIMARY KEY,
    #|  value TEXT NOT NULL
    #|);
    #|CREATE TABLE IF NOT EXISTS item_notes (
    #|  note_id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  item_id TEXT NOT NULL,
    #|  body TEXT NOT NULL,
    #|  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    #|  FOREIGN KEY(item_id) REFERENCES items(id) ON DELETE CASCADE
    #|);
    #|CREATE TABLE IF NOT EXISTS item_events (
    #|  event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  item_id TEXT NOT NULL,
    #|  event_type TEXT NOT NULL,
    #|  agent TEXT NOT NULL DEFAULT '',
    #|  body TEXT NOT NULL DEFAULT '',
    #|  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    #|  FOREIGN KEY(item_id) REFERENCES items(id) ON DELETE CASCADE
    #|);
    #|CREATE TABLE IF NOT EXISTS item_claims (
    #|  item_id TEXT PRIMARY KEY,
    #|  agent TEXT NOT NULL,
    #|  claimed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    #|  lease_until TEXT NOT NULL DEFAULT '',
    #|  FOREIGN KEY(item_id) REFERENCES items(id) ON DELETE CASCADE
    #|);
    #|
  ignore(sqlite_exec(db, schema))
}

///|
async fn migrate_numeric_id_db(db : String) -> Unit {
  if table_exists(db, "items_legacy_numeric") {
    cli_fail(
      "numeric id migration already has an items_legacy_numeric backup table",
    )
  }
  let legacy_items : Array[LegacyItemRow] = @json.from_json(
    sqlite_json(
      db, "SELECT id, title, status, priority FROM items ORDER BY id;",
    ),
  )
  let id_map : Map[String, String] = {}
  let title_map : Map[String, String] = {}
  for row in legacy_items {
    let title = normalize_title(row.title)
    let id = issue_id_from_title(title)
    match title_map.get(id) {
      Some(existing) =>
        if existing != title {
          cli_fail(
            "numeric id migration found SHA conflict between '\{existing}' and '\{title}'; rename one title before migrating",
          )
        } else {
          cli_fail(
            "numeric id migration found duplicate title '\{title}'; rename one title before migrating",
          )
        }
      None => {
        title_map[id] = title
        id_map[row.id.to_string()] = id
      }
    }
  }
  let legacy_edges : Array[LegacyEdgeRow] = if table_exists(db, "edges") {
    @json.from_json(
      sqlite_json(
        db, "SELECT from_id, to_id, kind FROM edges ORDER BY from_id;",
      ),
    )
  } else {
    []
  }
  let state_rows : Array[StateRow] = if table_exists(db, "state") {
    @json.from_json(
      sqlite_json(
        db, "SELECT value FROM state WHERE key='current_item_id' LIMIT 1;",
      ),
    )
  } else {
    []
  }
  let mut rename_sql = "PRAGMA foreign_keys = OFF; DROP TRIGGER IF EXISTS items_title_immutable; ALTER TABLE items RENAME TO items_legacy_numeric;"
  if table_exists(db, "edges") {
    rename_sql = rename_sql +
      " ALTER TABLE edges RENAME TO edges_legacy_numeric;"
  }
  if table_exists(db, "state") {
    rename_sql = rename_sql +
      " ALTER TABLE state RENAME TO state_legacy_numeric;"
  }
  ignore(sqlite_exec(db, rename_sql))
  ensure_schema(db)
  for row in legacy_items {
    let old_id = row.id.to_string()
    guard id_map.get(old_id) is Some(new_id) else { continue }
    let title = normalize_title(row.title)
    ignore(
      sqlite_exec(
        db,
        "INSERT INTO items(id, title, body, status, priority) VALUES(\{sql_quote(new_id)}, \{sql_quote(title)}, '', \{sql_quote(row.status)}, \{row.priority});",
      ),
    )
    append_event(
      db,
      new_id,
      "migrated",
      "migrated from numeric id \{row.id}",
      agent="",
    )
  }
  for edge in legacy_edges {
    let from_key = edge.from_id.to_string()
    let to_key = edge.to_id.to_string()
    guard id_map.get(from_key) is Some(from_id) else { continue }
    guard id_map.get(to_key) is Some(to_id) else { continue }
    ignore(
      sqlite_exec(
        db,
        "INSERT OR IGNORE INTO edges(from_id, to_id, kind) VALUES(\{sql_quote(from_id)}, \{sql_quote(to_id)}, \{sql_quote(edge.kind)});",
      ),
    )
  }
  match state_rows {
    [{ value, }, ..] =>
      match id_map.get(value) {
        Some(new_id) =>
          ignore(
            sqlite_exec(
              db,
              "INSERT INTO state(key, value) VALUES('current_item_id', \{sql_quote(new_id)});",
            ),
          )
        None => ()
      }
    [] => ()
  }
  let migrations =
    #|INSERT OR IGNORE INTO schema_migrations(version) VALUES('000_numeric_id_migration');
    #|INSERT OR IGNORE INTO schema_migrations(version) VALUES('001_deterministic_ids');
    #|INSERT OR IGNORE INTO schema_migrations(version) VALUES('002_agent_workflow');
    #|PRAGMA foreign_keys = ON;
    #|
  ignore(sqlite_exec(db, migrations))
}

///|
async fn table_exists(db : String, table : String) -> Bool {
  sqlite_scalar(
    db,
    "SELECT name FROM sqlite_master WHERE type='table' AND name=\{sql_quote(table)} LIMIT 1;",
  ) !=
  ""
}

///|
async fn table_has_column(db : String, table : String, column : String) -> Bool {
  let columns : Array[ColumnRow] = @json.from_json(
    sqlite_json(db, "PRAGMA table_info(\{table});"),
  )
  columns.any(col => col.name == column)
}

///|
async fn add_item(
  db : String,
  title : String,
  body : String,
  status : @issues.Status,
  priority : Int,
) -> String {
  init_db(db)
  let normalized_title = normalize_title(title)
  if normalized_title == "" {
    cli_fail("issue title must not be empty")
  }
  let id = issue_id_from_title(normalized_title)
  let quoted_id = sql_quote(id)
  let existing : Array[ExistingItemRow] = @json.from_json(
    sqlite_json(
      db,
      "SELECT id, title FROM items WHERE id=\{quoted_id} LIMIT 1;",
    ),
  )
  match existing {
    [row, ..] =>
      if row.title == normalized_title {
        row.id
      } else {
        cli_fail(
          "ISSUE_TITLE_RENAME_REQUIRED: SHA id \{id} already belongs to '\{row.title}'; ask the agent to rename '\{normalized_title}'",
        )
      }
    [] => {
      let quoted_title = sql_quote(normalized_title)
      let quoted_body = sql_quote(body)
      let quoted_status = sql_quote(status.to_storage())
      ignore(
        sqlite_exec(
          db,
          "INSERT INTO items(id, title, body, status, priority) VALUES(\{quoted_id}, \{quoted_title}, \{quoted_body}, \{quoted_status}, \{priority});",
        ),
      )
      append_event(
        db,
        id,
        "created",
        "created with status \{status.to_storage()} priority \{priority}",
        agent="",
      )
      id
    }
  }
}

///|
fn normalize_title(title : String) -> String {
  title.trim().to_owned()
}

///|
fn issue_id_from_title(title : String) -> String {
  let digest = @crypto.sha256(@utf8.encode(title))
  let hex = @crypto.bytes_to_hex_string(digest)
  "iss_" + hex.view(end_offset=16).to_owned()
}

///|
fn markdown_todos_from_string(source : String) -> Array[MarkdownTodo] {
  let doc = @cmark.Doc::from_string(strict=false, source)
  markdown_todos_from_block(doc.block)
}

///|
fn markdown_todos_from_block(block : @cmark.Block) -> Array[MarkdownTodo] {
  let todos : Array[MarkdownTodo] = []
  match block {
    @cmark.Block::Blocks(node) =>
      for child in node.v.to_array() {
        for todo in markdown_todos_from_block(child) {
          todos.push(todo)
        }
      }
    @cmark.Block::BlockQuote(node) =>
      for todo in markdown_todos_from_block(node.v.block) {
        todos.push(todo)
      }
    @cmark.Block::List(node) =>
      for item in node.v.items.to_array() {
        for todo in markdown_todos_from_list_item(item.v) {
          todos.push(todo)
        }
      }
    _ => ()
  }
  todos
}

///|
fn markdown_todos_from_list_item(item : @cmark.ListItem) -> Array[MarkdownTodo] {
  let (title, children) = markdown_item_content(item.block)
  match item.ext_task_marker {
    Some(marker) => {
      let title = title.trim().to_owned()
      if title == "" {
        cli_fail("markdown task item title must not be empty")
      }
      [{ title, status: markdown_task_status(marker.v), children, }]
    }
    None => children
  }
}

///|
fn markdown_item_content(block : @cmark.Block) -> (String, Array[MarkdownTodo]) {
  let mut title = ""
  let children : Array[MarkdownTodo] = []
  match block {
    @cmark.Block::Paragraph(node) => title = inline_plain_text(node.v.inline)
    @cmark.Block::Heading(node) => title = inline_plain_text(node.v.inline)
    @cmark.Block::Blocks(node) =>
      for child in node.v.to_array() {
        if title == "" {
          match child {
            @cmark.Block::Paragraph(node) =>
              title = inline_plain_text(node.v.inline)
            @cmark.Block::Heading(node) =>
              title = inline_plain_text(node.v.inline)
            _ => ()
          }
        }
        for todo in markdown_todos_from_block(child) {
          children.push(todo)
        }
      }
    _ =>
      for todo in markdown_todos_from_block(block) {
        children.push(todo)
      }
  }
  (title, children)
}

///|
fn inline_plain_text(inline : @cmark.Inline) -> String {
  let chunks : Array[String] = []
  for line in inline.to_plain_text(break_on_soft=false).to_array() {
    chunks.push(line.to_array().join(""))
  }
  chunks.join(" ").trim().to_owned()
}

///|
fn markdown_task_status(marker : Char) -> @issues.Status {
  match @cmark.ListTaskStatus::from_marker(marker) {
    @cmark.ListTaskStatus::Unchecked => Todo
    _ => Done
  }
}

///|
async fn import_markdown_todos(
  db : String,
  parent_id : String?,
  todos : Array[MarkdownTodo],
) -> String {
  init_db(db)
  if todos.length() == 0 {
    cli_fail("no markdown task list items found")
  }
  if parent_id is Some(id) {
    ignore(require_item(db, id))
  }
  let body = StringBuilder::new()
  let mut count = 0
  for todo in todos {
    count += import_markdown_todo(db, parent_id, todo, 0, body)
  }
  let report = StringBuilder::new()
  report.write_string("imported \{count} todos\n")
  report.write_string(body.to_string())
  report.to_string()
}

///|
async fn import_markdown_todo(
  db : String,
  parent_id : String?,
  todo : MarkdownTodo,
  depth : Int,
  report : StringBuilder,
) -> Int {
  let id = add_item(db, todo.title, "", todo.status, 0)
  if parent_id is Some(parent) {
    add_edge(db, parent, id, Contains)
  }
  for _ in 0..<depth {
    report.write_string("  ")
  }
  report.write_string("- #\{id} \{todo.title} [\{todo.status.to_storage()}]\n")
  let mut count = 1
  for child in todo.children {
    count += import_markdown_todo(db, Some(id), child, depth + 1, report)
  }
  count
}

///|
async fn add_edge(
  db : String,
  from_id : String,
  to_id : String,
  kind : @issues.EdgeKind,
) -> Unit {
  init_db(db)
  ignore(require_item(db, from_id))
  ignore(require_item(db, to_id))
  let quoted_from = sql_quote(from_id)
  let quoted_to = sql_quote(to_id)
  let quoted_kind = sql_quote(kind.to_storage())
  ignore(
    sqlite_exec(
      db,
      "INSERT OR IGNORE INTO edges(from_id, to_id, kind) VALUES(\{quoted_from}, \{quoted_to}, \{quoted_kind});",
    ),
  )
  append_event(
    db,
    from_id,
    "linked",
    "\{kind.to_storage()} -> #\{to_id}",
    agent="",
  )
  append_event(
    db,
    to_id,
    "linked",
    "#\{from_id} -> \{kind.to_storage()}",
    agent="",
  )
}

///|
async fn set_focus(db : String, id : String) -> Unit {
  init_db(db)
  let quoted_id = sql_quote(id)
  ignore(
    sqlite_exec(
      db,
      "INSERT INTO state(key, value) VALUES('current_item_id', \{quoted_id}) ON CONFLICT(key) DO UPDATE SET value=excluded.value;",
    ),
  )
}

///|
async fn set_body(db : String, id : String, body : String) -> Unit {
  init_db(db)
  ignore(require_item(db, id))
  ignore(
    sqlite_exec(
      db,
      "UPDATE items SET body=\{sql_quote(body)}, updated_at=CURRENT_TIMESTAMP WHERE id=\{sql_quote(id)};",
    ),
  )
  append_event(db, id, "body_updated", body, agent="")
}

///|
async fn add_note(db : String, id : String, body : String) -> Unit {
  init_db(db)
  ignore(require_item(db, id))
  let note = body.trim().to_owned()
  if note == "" {
    cli_fail("note must not be empty")
  }
  ignore(
    sqlite_exec(
      db,
      "INSERT INTO item_notes(item_id, body) VALUES(\{sql_quote(id)}, \{sql_quote(note)});",
    ),
  )
  append_event(db, id, "note_added", note, agent="")
}

///|
async fn set_status(
  db : String,
  id : String,
  status : @issues.Status,
  evidence : String?,
) -> Unit {
  init_db(db)
  let item = require_item(db, id)
  let evidence_text = evidence.unwrap_or("").trim().to_owned()
  if status == Done && evidence_text == "" {
    cli_fail(
      "done status requires evidence; use `done <item> <evidence>` or `status --evidence <text> <item> done`",
    )
  }
  let quoted_id = sql_quote(id)
  let quoted_status = sql_quote(status.to_storage())
  ignore(
    sqlite_exec(
      db,
      "UPDATE items SET status=\{quoted_status}, updated_at=CURRENT_TIMESTAMP WHERE id=\{quoted_id};",
    ),
  )
  let body = if evidence_text == "" {
    "\{item.status} -> \{status.to_storage()}"
  } else {
    "\{item.status} -> \{status.to_storage()}: \{evidence_text}"
  }
  append_event(db, id, "status_changed", body, agent="")
  if status == Done {
    let done_note = sql_quote("Done evidence: " + evidence_text)
    ignore(
      sqlite_exec(
        db,
        "INSERT INTO item_notes(item_id, body) VALUES(\{quoted_id}, \{done_note});",
      ),
    )
  }
}

///|
async fn require_item(db : String, id : String) -> ItemRow {
  let rows : Array[ItemRow] = @json.from_json(
    sqlite_json(
      db,
      "SELECT id, title, body, status, priority FROM items WHERE id=\{sql_quote(id)} LIMIT 1;",
    ),
  )
  match rows {
    [row, ..] => row
    [] => cli_fail("unknown issue id: \{id}")
  }
}

///|
async fn append_event(
  db : String,
  item_id : String,
  event_type : String,
  body : String,
  agent~ : String,
) -> Unit {
  ignore(
    sqlite_exec(
      db,
      "INSERT INTO item_events(item_id, event_type, agent, body) VALUES(\{sql_quote(item_id)}, \{sql_quote(event_type)}, \{sql_quote(agent)}, \{sql_quote(body)});",
    ),
  )
}

///|
async fn claim_item(
  db : String,
  id : String,
  agent : String,
  ttl_minutes : Int,
) -> Unit {
  init_db(db)
  ignore(require_item(db, id))
  let owner = agent.trim().to_owned()
  if owner == "" {
    cli_fail("claim agent must not be empty")
  }
  if ttl_minutes < 0 {
    cli_fail("ttl-minutes must be non-negative")
  }
  match active_claim(db, id) {
    Some(claim) =>
      if claim.agent != owner {
        let until = if claim.lease_until == "" {
          "without expiry"
        } else {
          "until \{claim.lease_until}"
        }
        cli_fail("ISSUE_CLAIMED: #\{id} is claimed by \{claim.agent} \{until}")
      }
    None => ()
  }
  let lease_sql = if ttl_minutes == 0 {
    "''"
  } else {
    "datetime('now', '+\{ttl_minutes} minutes')"
  }
  ignore(
    sqlite_exec(
      db,
      "INSERT INTO item_claims(item_id, agent, claimed_at, lease_until) VALUES(\{sql_quote(id)}, \{sql_quote(owner)}, CURRENT_TIMESTAMP, \{lease_sql}) ON CONFLICT(item_id) DO UPDATE SET agent=excluded.agent, claimed_at=excluded.claimed_at, lease_until=excluded.lease_until;",
    ),
  )
  append_event(
    db,
    id,
    "claimed",
    if ttl_minutes == 0 {
      "claimed without expiry"
    } else {
      "claimed for \{ttl_minutes} minutes"
    },
    agent=owner,
  )
}

///|
async fn release_item(db : String, id : String, agent : String) -> Unit {
  init_db(db)
  ignore(require_item(db, id))
  let owner = agent.trim().to_owned()
  match active_claim(db, id) {
    Some(claim) =>
      if owner != "" && claim.agent != owner {
        cli_fail(
          "ISSUE_CLAIMED: #\{id} is claimed by \{claim.agent}, not \{owner}",
        )
      }
    None => ()
  }
  ignore(
    sqlite_exec(db, "DELETE FROM item_claims WHERE item_id=\{sql_quote(id)};"),
  )
  append_event(db, id, "released", "claim released", agent=owner)
}

///|
async fn active_claim(db : String, id : String) -> ClaimRow? {
  let rows : Array[ClaimRow] = @json.from_json(
    sqlite_json(
      db,
      "SELECT item_id, agent, claimed_at, lease_until FROM item_claims WHERE item_id=\{sql_quote(id)} AND (lease_until='' OR lease_until > CURRENT_TIMESTAMP) LIMIT 1;",
    ),
  )
  match rows {
    [row, ..] => Some(row)
    [] => None
  }
}

///|
async fn load_notes(db : String, id : String, limit : Int) -> Array[NoteRow] {
  @json.from_json(
    sqlite_json(
      db,
      "SELECT note_id, body, created_at FROM item_notes WHERE item_id=\{sql_quote(id)} ORDER BY note_id DESC LIMIT \{limit};",
    ),
  )
}

///|
async fn load_events(db : String, id : String?, limit : Int) -> Array[EventRow] {
  let where_clause = match id {
    Some(value) => "WHERE item_id=\{sql_quote(value)}"
    None => ""
  }
  @json.from_json(
    sqlite_json(
      db,
      "SELECT event_id, item_id, event_type, agent, body, created_at FROM item_events \{where_clause} ORDER BY event_id DESC LIMIT \{limit};",
    ),
  )
}

///|
async fn load_graph(db : String) -> @issues.IssueGraph {
  init_db(db)
  let item_rows : Array[ItemRow] = @json.from_json(
    sqlite_json(
      db, "SELECT id, title, body, status, priority FROM items ORDER BY id;",
    ),
  )
  let edge_rows : Array[EdgeRow] = @json.from_json(
    sqlite_json(
      db, "SELECT from_id, to_id, kind FROM edges ORDER BY from_id, kind, to_id;",
    ),
  )
  let state_rows : Array[StateRow] = @json.from_json(
    sqlite_json(
      db, "SELECT value FROM state WHERE key='current_item_id' LIMIT 1;",
    ),
  )
  {
    items: item_rows.map(row => {
      id: row.id,
      title: row.title,
      body: row.body,
      status: @issues.Status::from_storage(row.status),
      priority: row.priority,
    }),
    edges: edge_rows.map(row => {
      from_id: row.from_id,
      to_id: row.to_id,
      kind: @issues.EdgeKind::from_storage(row.kind),
    }),
    current_id: match state_rows {
      [{ value, }, ..] => Some(value)
      [] => None
    },
  }
}

///|
async fn show_item(db : String, id : String) -> String {
  init_db(db)
  let graph = load_graph(db)
  let row = require_item(db, id)
  let item : @issues.IssueItem = {
    id: row.id,
    title: row.title,
    body: row.body,
    status: @issues.Status::from_storage(row.status),
    priority: row.priority,
  }
  let buf = StringBuilder()
  buf.write_string("#\{item.id} \{item.title}\n")
  buf.write_string("Status: \{item.status.to_storage()}\n")
  buf.write_string("Priority: \{item.priority}\n")
  match active_claim(db, id) {
    Some(claim) =>
      if claim.lease_until == "" {
        buf.write_string(
          "Claim: \{claim.agent} on #\{claim.item_id} since \{claim.claimed_at} (no expiry)\n",
        )
      } else {
        buf.write_string(
          "Claim: \{claim.agent} on #\{claim.item_id} since \{claim.claimed_at} until \{claim.lease_until}\n",
        )
      }
    None => buf.write_string("Claim: none\n")
  }
  if item.body.trim().to_owned() != "" {
    buf.write_string("\nBody:\n")
    write_indented(buf, item.body)
  }
  write_relation_section(
    buf,
    "Parents",
    relation_items(graph, id, parent=true, Contains),
  )
  write_relation_section(buf, "Subtasks", graph.contains_children(id))
  write_relation_section(buf, "Dependencies", graph.dependencies(id))
  let blockers = graph.dependencies(id).filter(dep => dep.status.is_open())
  write_relation_section(buf, "Open blockers", blockers)
  let notes = load_notes(db, id, 10)
  buf.write_string("\nNotes:\n")
  if notes.length() == 0 {
    buf.write_string("- none\n")
  } else {
    for note in notes {
      buf.write_string(
        "- \{note.created_at} #\{note.note_id}: \{one_line(note.body)}\n",
      )
    }
  }
  buf.write_string("\nRecent events:\n")
  let events = load_events(db, Some(id), 10)
  if events.length() == 0 {
    buf.write_string("- none\n")
  } else {
    for event in events {
      let agent = if event.agent == "" { "" } else { " by \{event.agent}" }
      let body = if event.body == "" { "" } else { ": \{one_line(event.body)}" }
      buf.write_string(
        "- @\{event.event_id} \{event.created_at} \{event.event_type}\{agent}\{body}\n",
      )
    }
  }
  buf.to_string()
}

///|
fn write_relation_section(
  buf : StringBuilder,
  title : String,
  items : Array[@issues.IssueItem],
) -> Unit {
  buf.write_string("\n\{title}:\n")
  if items.length() == 0 {
    buf.write_string("- none\n")
  } else {
    for item in items {
      buf.write_string(
        "- [\{item.status.to_storage()}] #\{item.id} \{item.title} (p\{item.priority})\n",
      )
    }
  }
}

///|
fn relation_items(
  graph : @issues.IssueGraph,
  id : String,
  parent~ : Bool,
  kind : @issues.EdgeKind,
) -> Array[@issues.IssueItem] {
  let items : Array[@issues.IssueItem] = []
  for edge in graph.edges {
    if edge.kind == kind {
      let candidate = if parent && edge.to_id == id {
        graph.find_item(edge.from_id)
      } else if !parent && edge.from_id == id {
        graph.find_item(edge.to_id)
      } else {
        None
      }
      match candidate {
        Some(item) => items.push(item)
        None => ()
      }
    }
  }
  items
}

///|
fn write_indented(buf : StringBuilder, value : String) -> Unit {
  for line in value.split("\n") {
    buf.write_string("  \{line}\n")
  }
}

///|
fn one_line(value : String) -> String {
  value.replace_all(old="\n", new=" ").trim().to_owned()
}

///|
async fn events_view(db : String, id : String?, limit : Int) -> String {
  init_db(db)
  match id {
    Some(value) => ignore(require_item(db, value))
    None => ()
  }
  let rows = load_events(db, id, limit)
  if rows.length() == 0 {
    "no events\n"
  } else {
    let buf = StringBuilder()
    for event in rows {
      let agent = if event.agent == "" { "" } else { " by \{event.agent}" }
      let body = if event.body == "" { "" } else { ": \{one_line(event.body)}" }
      buf.write_string(
        "@\{event.event_id} \{event.created_at} #\{event.item_id} \{event.event_type}\{agent}\{body}\n",
      )
    }
    buf.to_string()
  }
}

///|
async fn search_view(db : String, query : String) -> String {
  init_db(db)
  let needle = query.trim().to_owned()
  if needle == "" {
    cli_fail("search query must not be empty")
  }
  let pattern = sql_quote("%" + needle.to_lower() + "%")
  let search_template =
    #|SELECT DISTINCT items.id, items.title, items.body, items.status, items.priority
    #|FROM items
    #|LEFT JOIN item_notes ON item_notes.item_id = items.id
    #|LEFT JOIN item_events ON item_events.item_id = items.id
    #|WHERE lower(items.id) LIKE \#(pattern)
    #|   OR lower(items.title) LIKE \#(pattern)
    #|   OR lower(items.body) LIKE \#(pattern)
    #|   OR lower(item_notes.body) LIKE \#(pattern)
    #|   OR lower(item_events.body) LIKE \#(pattern)
    #|ORDER BY items.status, items.priority DESC, items.id;
    #|
  let search_sql = search_template.replace_all(old="\\#(pattern)", new=pattern)
  let rows : Array[ItemRow] = @json.from_json(sqlite_json(db, search_sql))
  if rows.length() == 0 {
    "no matches\n"
  } else {
    let buf = StringBuilder()
    for row in rows {
      buf.write_string(
        "#\{row.id} \{row.title} [\{row.status} p\{row.priority}]\n",
      )
    }
    buf.to_string()
  }
}

///|
async fn write_dashboard_files(db : String, out_dir : String) -> Unit {
  let graph = load_graph(db)
  let app_js_path = build_dashboard_app()
  @fs.mkdir(out_dir, recursive=true)
  @fs.write_file(
    "\{out_dir}/data.js",
    "window.__ISSUES_DATA__ = \{graph.to_json().stringify(indent=2)};\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{out_dir}/index.html",
    dashboard_html(),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{out_dir}/app.js",
    @fs.read_file(app_js_path),
    create_mode=CreateOrTruncate,
  )
}

///|
async fn serve_dashboard(db : String, host : String, port : Int) -> Unit {
  init_db(db)
  let app_js = @fs.read_file(build_dashboard_app()).text()
  let addr = @socket.Addr::parse("\{host}:\{port}")
  let server = @http.Server(addr, reuse_addr=true, headers={
    "Cache-Control": "no-store",
  })
  server.run_forever((request, body, conn) => {
    let path = strip_query(request.path)
    match request.meth {
      Get => serve_dashboard_get(db, app_js, path, conn)
      Post => serve_dashboard_post(db, path, body, conn)
      _ =>
        send_text(
          conn, 405, "Method Not Allowed", "method not allowed\n", "text/plain",
        )
    }
  })
}

///|
async fn serve_dashboard_get(
  db : String,
  app_js : String,
  path : String,
  conn : @http.ServerConnection,
) -> Unit {
  match path {
    "/" | "/index.html" =>
      send_text(conn, 200, "OK", dashboard_html(), "text/html")
    "/app.js" => send_text(conn, 200, "OK", app_js, "text/javascript")
    "/data.js" => {
      let graph = load_graph(db)
      let body = "window.__ISSUES_DATA__ = \{graph.to_json().stringify(indent=2)};\n"
      send_text(conn, 200, "OK", body, "text/javascript")
    }
    "/api/graph" => send_graph_json(db, conn)
    "/api/next" => {
      let graph = load_graph(db)
      let body = match graph.next_todo(None) {
        Some(item) => item.to_json().stringify(indent=2) + "\n"
        None => "null\n"
      }
      send_text(conn, 200, "OK", body, "application/json")
    }
    "/api/outline" =>
      send_text(conn, 200, "OK", load_graph(db).outline(None), "text/plain")
    "/healthz" => send_text(conn, 200, "OK", "ok\n", "text/plain")
    _ => send_text(conn, 404, "Not Found", "not found\n", "text/plain")
  }
}

///|
async fn serve_dashboard_post(
  db : String,
  path : String,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let json = @json.parse(body.read_all().text())
  match path {
    "/api/body" => {
      let payload : BodyPayload = @json.from_json(json)
      set_body(db, payload.id, payload.body)
      send_graph_json(db, conn)
    }
    "/api/note" => {
      let payload : NotePayload = @json.from_json(json)
      add_note(db, payload.id, payload.body)
      send_graph_json(db, conn)
    }
    "/api/status" => {
      let payload : StatusPayload = @json.from_json(json)
      let status = @issues.Status::from_storage(payload.status)
      set_status(db, payload.id, status, Some(payload.evidence))
      send_graph_json(db, conn)
    }
    _ => send_text(conn, 404, "Not Found", "not found\n", "text/plain")
  }
}

///|
async fn send_graph_json(db : String, conn : @http.ServerConnection) -> Unit {
  let graph = load_graph(db)
  send_text(
    conn,
    200,
    "OK",
    graph.to_json().stringify(indent=2) + "\n",
    "application/json",
  )
}

///|
fn strip_query(path : String) -> String {
  match path.split_once("?") {
    Some((head, _)) => head.to_owned()
    None => path
  }
}

///|
async fn send_text(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  body : String,
  content_type : String,
) -> Unit {
  conn
  ..send_response(code, reason, extra_headers={ "Content-Type": content_type })
  ..write(body)
  .end_response()
}

///|
async fn build_dashboard_app() -> String {
  let (code, _, stderr) = @process.collect_output("moon", [
    "build", "--target", "js", "dashboard/app",
  ])
  if code != 0 {
    cli_fail("failed to build dashboard/app: \{stderr.text()}")
  }
  "_build/js/debug/build/dashboard/app/app.js"
}

///|
fn dashboard_html() -> String {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|<head>
    #|  <meta charset="utf-8">
    #|  <meta name="viewport" content="width=device-width, initial-scale=1">
    #|  <title>Issues Dashboard</title>
    #|  <script src="./data.js"></script>
    #|  <script defer src="./app.js"></script>
    #|</head>
    #|<body>
    #|  <main id="app"></main>
    #|</body>
    #|</html>
    #|
  html
}

///|
async fn sqlite_json(db : String, sql : String) -> Json {
  let output = sqlite_stdout_with_args(["-batch", "-json", db, sql])
  let text = output.trim().to_owned()
  if text == "" {
    Json::array([])
  } else {
    @json.parse(text)
  }
}

///|
async fn sqlite_scalar(db : String, sql : String) -> String {
  sqlite_stdout_with_args(["-batch", "-noheader", db, sql]).trim().to_owned()
}

///|
async fn sqlite_exec(db : String, sql : String) -> String {
  sqlite_stdout_with_args(["-batch", db, sql])
}

///|
async fn sqlite_stdout_with_args(args : Array[String]) -> String {
  let (code, stdout, stderr) = @process.collect_output("sqlite3", args)
  if code != 0 {
    let err = stderr.text()
    cli_fail("sqlite3 failed: \{err}")
  }
  stdout.text()
}

///|
fn sql_quote(value : String) -> String {
  let escaped = value.replace_all(old="'", new="''")
  "'\{escaped}'"
}
