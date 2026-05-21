///|
using @html {
  aside,
  button,
  div,
  h1,
  h2,
  h3,
  header,
  li,
  main_,
  p,
  section,
  span,
  strong,
  text,
  ul,
}

///|
pub(all) struct Model {
  graph : @issues.IssueGraph
  selected_id : String?
} derive(Debug)

///|
pub(all) enum Msg {
  Select(String)
} derive(Debug)

///|
pub fn app(graph : @issues.IssueGraph) -> @rabbita.Cell {
  @rabbita.simple_cell(
    model={ graph, selected_id: graph.next_todo(None).map(item => item.id) },
    update=(msg, model) => {
      match msg {
        Select(id) => { ..model, selected_id: Some(id) }
      }
    },
    view~,
  )
}

///|
pub fn render_static(graph : @issues.IssueGraph) -> String {
  @rabbita.render_to_string(app(graph))
}

///|
pub fn graph_from_json_string(source : String) -> @issues.IssueGraph raise {
  @json.from_json(@json.parse(source))
}

///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let graph = model.graph
  main_(style=page_style(), [
    header(style=header_style(), [
      div([
        h1(style=["margin: 0", "font-size: 24px"], "Issues Dashboard"),
        p(style=["margin: 6px 0 0", "color: #53606f"], current_label(graph)),
      ]),
      div(style=stats_style(), [
        stat("Open", graph.open_count().to_string()),
        stat("Blocked", graph.blocked_count().to_string()),
        stat("Contains", graph.edge_count(Contains).to_string()),
      ]),
    ]),
    div(style=shell_style(), [
      aside(style=sidebar_style(), [
        h2(style=panel_title_style(), "Outline"),
        ul(
          style=["list-style: none", "margin: 0", "padding: 0"],
          outline_nodes(emit, graph, model.selected_id),
        ),
      ]),
      section(style=detail_style(), [
        h2(style=panel_title_style(), "Selected"),
        detail_view(graph, model.selected_id),
      ]),
    ]),
  ])
}

///|
fn outline_nodes(
  emit : @rabbita.Emit[Msg],
  graph : @issues.IssueGraph,
  selected_id : String?,
) -> Array[@html.Html] {
  root_items(graph).map(item => outline_node(emit, graph, item, selected_id, 0))
}

///|
fn outline_node(
  emit : @rabbita.Emit[Msg],
  graph : @issues.IssueGraph,
  item : @issues.IssueItem,
  selected_id : String?,
  depth : Int,
) -> @html.Html {
  let children = graph.contains_children(item.id)
  let is_selected = selected_id == Some(item.id)
  let row_style = if is_selected {
    [
      "width: 100%", "text-align: left", "border: 1px solid #2563eb", "background: #eff6ff",
      "padding: 8px", "cursor: pointer",
    ]
  } else {
    [
      "width: 100%", "text-align: left", "border: 1px solid transparent", "background: transparent",
      "padding: 8px", "cursor: pointer",
    ]
  }
  li(style=["margin-left: \{depth * 14}px", "margin-bottom: 4px"], [
    button(on_click=emit(Select(item.id)), style=row_style, [
      span(style=badge_style(item.status), status_label(item.status)),
      span(style=["margin-left: 8px", "font-weight: 600"], "#\{item.id}"),
      span(style=["margin-left: 8px"], item.title),
    ]),
    ul(
      style=["list-style: none", "margin: 4px 0 0", "padding: 0"],
      children.map(child => {
        outline_node(emit, graph, child, selected_id, depth + 1)
      }),
    ),
  ])
}

///|
fn detail_view(graph : @issues.IssueGraph, selected_id : String?) -> @html.Html {
  let selected = match selected_id {
    Some(id) => graph.find_item(id)
    None => graph.next_todo(None)
  }
  match selected {
    None => p(style=["color: #53606f"], "No actionable todo is available.")
    Some(item) => {
      let blocked = graph.is_blocked(item.id)
      div([
        div(style=["display: flex", "gap: 8px", "align-items: center"], [
          span(style=badge_style(item.status), status_label(item.status)),
          span(
            style=if blocked {
              blocked_badge_style()
            } else {
              quiet_badge_style()
            },
            if blocked {
              "blocked"
            } else {
              "ready"
            },
          ),
        ]),
        h3(
          style=["margin: 14px 0 4px", "font-size: 22px"],
          "#\{item.id} \{item.title}",
        ),
        p(
          style=["margin: 0 0 18px", "color: #53606f"],
          "Priority \{item.priority}",
        ),
        if item.body.trim().to_owned() == "" {
          p(style=["display: none"], "")
        } else {
          p(
            style=[
              "margin: 0 0 18px", "color: #374151", "white-space: pre-wrap", "line-height: 1.5",
            ],
            item.body,
          )
        },
        relation_list("Subtasks", graph.contains_children(item.id)),
        relation_list("Dependencies", graph.dependencies(item.id)),
      ])
    }
  }
}

///|
fn relation_list(
  title : String,
  items : Array[@issues.IssueItem],
) -> @html.Html {
  section(style=["margin-top: 18px"], [
    h3(style=["font-size: 14px", "margin: 0 0 8px", "color: #1f2937"], title),
    if items.length() == 0 {
      p(style=["margin: 0", "color: #6b7280"], "None")
    } else {
      ul(
        style=["margin: 0", "padding-left: 18px"],
        items.map(item => {
          li([
            strong("#\{item.id}"),
            text(" \{item.title} "),
            span(style=badge_style(item.status), status_label(item.status)),
          ])
        }),
      )
    },
  ])
}

///|
fn root_items(graph : @issues.IssueGraph) -> Array[@issues.IssueItem] {
  match graph.current_id {
    Some(id) =>
      match graph.find_item(id) {
        Some(item) => [item]
        None => graph.items
      }
    None => {
      let has_parent : Map[String, Unit] = {}
      for edge in graph.edges {
        if edge.kind == Contains {
          has_parent[edge.to_id] = ()
        }
      }
      let roots = graph.items.filter(item => !has_parent.contains(item.id))
      if roots.length() == 0 {
        graph.items
      } else {
        roots
      }
    }
  }
}

///|
fn current_label(graph : @issues.IssueGraph) -> String {
  match graph.current_id {
    Some(id) => "Current focus: #\{id}"
    None => "No current focus set"
  }
}

///|
fn stat(label : String, value : String) -> @html.Html {
  div(style=["min-width: 92px"], [
    div(style=["font-size: 20px", "font-weight: 700"], value),
    div(style=["font-size: 12px", "color: #64748b"], label),
  ])
}

///|
fn status_label(status : @issues.Status) -> String {
  match status {
    Todo => "todo"
    InProgress => "active"
    Done => "done"
  }
}

///|
fn badge_style(status : @issues.Status) -> Array[String] {
  let color = match status {
    Todo => "#d97706"
    InProgress => "#2563eb"
    Done => "#15803d"
  }
  [
    "display: inline-block",
    "font-size: 12px",
    "line-height: 1",
    "border: 1px solid \{color}",
    "color: \{color}",
    "padding: 3px 6px",
  ]
}

///|
fn blocked_badge_style() -> Array[String] {
  [
    "display: inline-block", "font-size: 12px", "line-height: 1", "border: 1px solid #dc2626",
    "color: #dc2626", "padding: 3px 6px",
  ]
}

///|
fn quiet_badge_style() -> Array[String] {
  [
    "display: inline-block", "font-size: 12px", "line-height: 1", "border: 1px solid #64748b",
    "color: #475569", "padding: 3px 6px",
  ]
}

///|
fn page_style() -> Array[String] {
  [
    "font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif",
    "min-height: 100vh", "background: #f8fafc", "color: #111827", "padding: 24px",
    "box-sizing: border-box",
  ]
}

///|
fn header_style() -> Array[String] {
  [
    "display: flex", "justify-content: space-between", "gap: 16px", "align-items: flex-start",
    "margin-bottom: 18px",
  ]
}

///|
fn stats_style() -> Array[String] {
  [
    "display: flex", "gap: 12px", "background: #ffffff", "border: 1px solid #e5e7eb",
    "padding: 12px",
  ]
}

///|
fn shell_style() -> Array[String] {
  [
    "display: grid", "grid-template-columns: minmax(280px, 36%) minmax(0, 1fr)",
    "gap: 18px", "align-items: start",
  ]
}

///|
fn sidebar_style() -> Array[String] {
  ["background: #ffffff", "border: 1px solid #e5e7eb", "padding: 14px"]
}

///|
fn detail_style() -> Array[String] {
  [
    "background: #ffffff", "border: 1px solid #e5e7eb", "padding: 18px", "min-height: 260px",
  ]
}

///|
fn panel_title_style() -> Array[String] {
  [
    "font-size: 14px", "text-transform: uppercase", "letter-spacing: 0", "color: #475569",
    "margin: 0 0 12px",
  ]
}
