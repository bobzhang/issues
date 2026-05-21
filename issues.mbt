///|
pub(all) enum Status {
  Todo
  InProgress
  Done
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn Status::from_storage(value : String) -> Status raise {
  match value {
    "todo" | "Todo" => Todo
    "in-progress" | "in_progress" | "InProgress" => InProgress
    "done" | "Done" => Done
    other => fail("unknown status: \{other}")
  }
}

///|
pub fn Status::to_storage(self : Status) -> String {
  match self {
    Todo => "todo"
    InProgress => "in-progress"
    Done => "done"
  }
}

///|
pub fn Status::is_open(self : Status) -> Bool {
  self != Done
}

///|
fn Status::rank_for_next(self : Status) -> Int {
  match self {
    InProgress => 0
    Todo => 1
    Done => 2
  }
}

///|
pub(all) enum EdgeKind {
  Contains
  DependsOn
  RelatesTo
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn EdgeKind::from_storage(value : String) -> EdgeKind raise {
  match value {
    "contains" | "Contains" => Contains
    "depends_on" | "depends-on" | "DependsOn" => DependsOn
    "relates_to" | "relates-to" | "RelatesTo" => RelatesTo
    other => fail("unknown edge kind: \{other}")
  }
}

///|
pub fn EdgeKind::to_storage(self : EdgeKind) -> String {
  match self {
    Contains => "contains"
    DependsOn => "depends_on"
    RelatesTo => "relates_to"
  }
}

///|
pub(all) struct IssueItem {
  id : String
  title : String
  status : Status
  priority : Int
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct IssueEdge {
  from_id : String
  to_id : String
  kind : EdgeKind
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct IssueGraph {
  items : Array[IssueItem]
  edges : Array[IssueEdge]
  current_id : String?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub fn IssueGraph::empty() -> IssueGraph {
  { items: [], edges: [], current_id: None }
}

///|
pub fn IssueGraph::find_item(self : IssueGraph, id : String) -> IssueItem? {
  for item in self.items {
    if item.id == id {
      return Some(item)
    }
  }
  None
}

///|
pub fn IssueGraph::contains_children(
  self : IssueGraph,
  id : String,
) -> Array[IssueItem] {
  let children : Array[IssueItem] = []
  for edge in self.edges {
    if edge.kind == Contains && edge.from_id == id {
      match self.find_item(edge.to_id) {
        Some(item) => children.push(item)
        None => ()
      }
    }
  }
  sort_items_for_display(children)
  children
}

///|
pub fn IssueGraph::dependencies(
  self : IssueGraph,
  id : String,
) -> Array[IssueItem] {
  let deps : Array[IssueItem] = []
  for edge in self.edges {
    if edge.kind == DependsOn && edge.from_id == id {
      match self.find_item(edge.to_id) {
        Some(item) => deps.push(item)
        None => ()
      }
    }
  }
  sort_items_for_display(deps)
  deps
}

///|
pub fn IssueGraph::is_blocked(self : IssueGraph, id : String) -> Bool {
  for dep in self.dependencies(id) {
    if dep.status.is_open() {
      return true
    }
  }
  false
}

///|
pub fn IssueGraph::has_open_child(self : IssueGraph, id : String) -> Bool {
  for child in self.contains_children(id) {
    if child.status.is_open() {
      return true
    }
  }
  false
}

///|
pub fn IssueGraph::next_todo(self : IssueGraph, focus : String?) -> IssueItem? {
  let scoped = self.scoped_item_ids(focus)
  let candidates : Array[IssueItem] = []
  for item in self.items {
    if scoped.contains(item.id) &&
      item.status.is_open() &&
      !self.is_blocked(item.id) &&
      !self.has_open_child(item.id) {
      candidates.push(item)
    }
  }
  candidates.sort_by(compare_next_candidate)
  match candidates {
    [first, ..] => Some(first)
    [] => None
  }
}

///|
pub fn IssueGraph::outline(self : IssueGraph, focus : String?) -> String {
  let roots = self.outline_roots(focus)
  let buf = StringBuilder()
  let seen : Map[String, Unit] = {}
  for root in roots {
    write_outline_node(self, root.id, 0, buf, seen)
  }
  buf.to_string()
}

///|
pub fn IssueGraph::open_count(self : IssueGraph) -> Int {
  self.items.fold(init=0, (count, item) => {
    if item.status.is_open() {
      count + 1
    } else {
      count
    }
  })
}

///|
pub fn IssueGraph::blocked_count(self : IssueGraph) -> Int {
  self.items.fold(init=0, (count, item) => {
    if item.status.is_open() && self.is_blocked(item.id) {
      count + 1
    } else {
      count
    }
  })
}

///|
pub fn IssueGraph::edge_count(self : IssueGraph, kind : EdgeKind) -> Int {
  self.edges.fold(init=0, (count, edge) => {
    if edge.kind == kind {
      count + 1
    } else {
      count
    }
  })
}

///|
fn IssueGraph::scoped_item_ids(
  self : IssueGraph,
  focus : String?,
) -> Map[String, Unit] {
  let seen : Map[String, Unit] = {}
  match resolve_focus(focus, self.current_id) {
    Some(root) => collect_contains_scope(self, root, seen)
    None =>
      for item in self.items {
        seen[item.id] = ()
      }
  }
  seen
}

///|
fn IssueGraph::outline_roots(
  self : IssueGraph,
  focus : String?,
) -> Array[IssueItem] {
  match resolve_focus(focus, self.current_id) {
    Some(id) =>
      match self.find_item(id) {
        Some(item) => [item]
        None => []
      }
    None => {
      let has_parent : Map[String, Unit] = {}
      for edge in self.edges {
        if edge.kind == Contains {
          has_parent[edge.to_id] = ()
        }
      }
      let roots = self.items.filter(item => !has_parent.contains(item.id))
      if roots.length() == 0 {
        let all = self.items.copy()
        sort_items_for_display(all)
        all
      } else {
        sort_items_for_display(roots)
        roots
      }
    }
  }
}

///|
fn collect_contains_scope(
  graph : IssueGraph,
  id : String,
  seen : Map[String, Unit],
) -> Unit {
  if seen.contains(id) {
    return
  }
  seen[id] = ()
  for edge in graph.edges {
    if edge.kind == Contains && edge.from_id == id {
      collect_contains_scope(graph, edge.to_id, seen)
    }
  }
}

///|
fn resolve_focus(focus : String?, current : String?) -> String? {
  match focus {
    Some(_) => focus
    None => current
  }
}

///|
fn write_outline_node(
  graph : IssueGraph,
  id : String,
  depth : Int,
  buf : StringBuilder,
  seen : Map[String, Unit],
) -> Unit {
  let indent = "  ".repeat(depth)
  if seen.contains(id) {
    buf.write_string("\{indent}- \{id} (cycle)\n")
    return
  }
  seen[id] = ()
  match graph.find_item(id) {
    None => buf.write_string("\{indent}- \{id} (missing)\n")
    Some(item) => {
      let blocked = if graph.is_blocked(id) { " blocked" } else { "" }
      let current = if graph.current_id == Some(id) { " current" } else { "" }
      let status = item.status.to_storage()
      buf.write_string(
        "\{indent}- [\{status}] #\{item.id} \{item.title} (p\{item.priority}\{blocked}\{current})\n",
      )
      for child in graph.contains_children(id) {
        write_outline_node(graph, child.id, depth + 1, buf, seen)
      }
    }
  }
}

///|
fn sort_items_for_display(items : Array[IssueItem]) -> Unit {
  items.sort_by((left, right) => {
    let by_priority = right.priority.compare(left.priority)
    if by_priority != 0 {
      by_priority
    } else {
      left.id.compare(right.id)
    }
  })
}

///|
fn compare_next_candidate(left : IssueItem, right : IssueItem) -> Int {
  let by_status = left.status
    .rank_for_next()
    .compare(right.status.rank_for_next())
  if by_status != 0 {
    by_status
  } else {
    let by_priority = right.priority.compare(left.priority)
    if by_priority != 0 {
      by_priority
    } else {
      left.id.compare(right.id)
    }
  }
}
