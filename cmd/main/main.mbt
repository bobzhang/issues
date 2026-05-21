///|
struct ItemRow {
  id : Int
  title : String
  status : String
  priority : Int
} derive(FromJson)

///|
struct EdgeRow {
  from_id : Int
  to_id : Int
  kind : String
} derive(FromJson)

///|
struct StateRow {
  value : String
} derive(FromJson)

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
      let id = add_item(db, title, status, priority)
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
    "status" => {
      let id = require_one(sub, "item")
      let status = @issues.Status::from_storage(require_one(sub, "status"))
      set_status(db, id, status)
      println("#\{id} \{status.to_storage()}")
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
    other => fail("unhandled subcommand: \{other}")
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
    version="0.1.0",
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
        "status",
        about="Set item status: todo, in-progress, or done.",
        positionals=[
          item_arg,
          @argparse.PositionArg(
            "status",
            num_args=@argparse.ValueRange::single(),
          ),
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
fn require_one(matches : @argparse.Matches, name : String) -> String raise {
  match get_one(matches, name) {
    Some(value) => value
    None => fail("missing argument: \{name}")
  }
}

///|
async fn init_db(db : String) -> Unit {
  let schema =
    #|PRAGMA foreign_keys = ON;
    #|CREATE TABLE IF NOT EXISTS items (
    #|  id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  title TEXT NOT NULL,
    #|  status TEXT NOT NULL DEFAULT 'todo',
    #|  priority INTEGER NOT NULL DEFAULT 0,
    #|  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    #|  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    #|);
    #|CREATE TABLE IF NOT EXISTS edges (
    #|  from_id INTEGER NOT NULL,
    #|  to_id INTEGER NOT NULL,
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
    #|
  ignore(sqlite_exec(db, schema))
}

///|
async fn add_item(
  db : String,
  title : String,
  status : @issues.Status,
  priority : Int,
) -> String {
  init_db(db)
  let quoted_title = sql_quote(title)
  let quoted_status = sql_quote(status.to_storage())
  let sql = "INSERT INTO items(title, status, priority) VALUES(\{quoted_title}, \{quoted_status}, \{priority}); SELECT last_insert_rowid();"
  sqlite_scalar(db, sql)
}

///|
async fn add_edge(
  db : String,
  from_id : String,
  to_id : String,
  kind : @issues.EdgeKind,
) -> Unit {
  init_db(db)
  let quoted_from = sql_quote(from_id)
  let quoted_to = sql_quote(to_id)
  let quoted_kind = sql_quote(kind.to_storage())
  ignore(
    sqlite_exec(
      db,
      "INSERT OR IGNORE INTO edges(from_id, to_id, kind) VALUES(\{quoted_from}, \{quoted_to}, \{quoted_kind});",
    ),
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
async fn set_status(db : String, id : String, status : @issues.Status) -> Unit {
  init_db(db)
  let quoted_id = sql_quote(id)
  let quoted_status = sql_quote(status.to_storage())
  ignore(
    sqlite_exec(
      db,
      "UPDATE items SET status=\{quoted_status}, updated_at=CURRENT_TIMESTAMP WHERE id=\{quoted_id};",
    ),
  )
}

///|
async fn load_graph(db : String) -> @issues.IssueGraph {
  init_db(db)
  let item_rows : Array[ItemRow] = @json.from_json(
    sqlite_json(
      db, "SELECT id, title, status, priority FROM items ORDER BY id;",
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
      id: row.id.to_string(),
      title: row.title,
      status: @issues.Status::from_storage(row.status),
      priority: row.priority,
    }),
    edges: edge_rows.map(row => {
      from_id: row.from_id.to_string(),
      to_id: row.to_id.to_string(),
      kind: @issues.EdgeKind::from_storage(row.kind),
    }),
    current_id: match state_rows {
      [{ value }, ..] => Some(value)
      [] => None
    },
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
  server.run_forever((request, _body, conn) => {
    guard request.meth is Get else {
      send_text(
        conn, 405, "Method Not Allowed", "method not allowed\n", "text/plain",
      )
      return
    }
    let path = strip_query(request.path)
    match path {
      "/" | "/index.html" =>
        send_text(conn, 200, "OK", dashboard_html(), "text/html")
      "/app.js" => send_text(conn, 200, "OK", app_js, "text/javascript")
      "/data.js" => {
        let graph = load_graph(db)
        let body = "window.__ISSUES_DATA__ = \{graph.to_json().stringify(indent=2)};\n"
        send_text(conn, 200, "OK", body, "text/javascript")
      }
      "/api/graph" => {
        let graph = load_graph(db)
        send_text(
          conn,
          200,
          "OK",
          graph.to_json().stringify(indent=2) + "\n",
          "application/json",
        )
      }
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
  })
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
    fail("failed to build dashboard/app: \{stderr.text()}")
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
    fail("sqlite3 failed: \{err}")
  }
  stdout.text()
}

///|
fn sql_quote(value : String) -> String {
  let escaped = value.replace_all(old="'", new="''")
  "'\{escaped}'"
}
