///|
fn sample_graph() -> @issues.IssueGraph {
  {
    items: [
      { id: "1", title: "Build tracker", body: "", status: Todo, priority: 5 },
      { id: "2", title: "Design schema", body: "", status: Done, priority: 3 },
      { id: "3", title: "Implement CLI", body: "", status: Todo, priority: 8 },
      {
        id: "4",
        title: "Implement dashboard",
        body: "",
        status: Todo,
        priority: 6,
      },
      {
        id: "5",
        title: "Pick visual layout",
        body: "",
        status: Todo,
        priority: 4,
      },
    ],
    edges: [
      { from_id: "1", to_id: "2", kind: Contains },
      { from_id: "1", to_id: "3", kind: Contains },
      { from_id: "1", to_id: "4", kind: Contains },
      { from_id: "4", to_id: "5", kind: Contains },
      { from_id: "3", to_id: "2", kind: DependsOn },
      { from_id: "4", to_id: "3", kind: DependsOn },
    ],
    current_id: Some("1"),
  }
}

///|
test "next todo chooses highest priority unblocked leaf in focus" {
  let graph = sample_graph()
  inspect(
    match graph.next_todo(None) {
      Some(item) => item.id
      None => "none"
    },
    content="3",
  )
}

///|
test "blocked parent does not hide actionable child leaf" {
  let graph = sample_graph()
  inspect(graph.is_blocked("4"), content="true")
  inspect(
    match graph.next_todo(Some("4")) {
      Some(item) => item.id
      None => "none"
    },
    content="5",
  )
}

///|
test "todo views filter ready blocked and all scoped items" {
  let graph = sample_graph()
  inspect(graph.ready_todos(None).map(item => item.id).join(","), content="3,5")
  inspect(graph.blocked_todos(None).map(item => item.id).join(","), content="4")
  inspect(
    graph.all_todos_markdown(Some("4")),
    content=(
      #|- [ ] #4 Implement dashboard (p6 blocked)
      #|- [ ] #5 Pick visual layout (p4)
      #|
    ),
  )
}

///|
test "outline renders contains tree with current and blocked markers" {
  inspect(
    sample_graph().outline(None),
    content=(
      #|- [todo] #1 Build tracker (p5 current)
      #|  - [todo] #3 Implement CLI (p8)
      #|  - [todo] #4 Implement dashboard (p6 blocked)
      #|    - [todo] #5 Pick visual layout (p4)
      #|  - [done] #2 Design schema (p3)
      #|
    ),
  )
}

///|
test "todos markdown renders recursive task list" {
  inspect(
    sample_graph().todos_markdown(None),
    content=(
      #|- [ ] #1 Build tracker (p5 current)
      #|  - [ ] #3 Implement CLI (p8)
      #|  - [ ] #4 Implement dashboard (p6 blocked)
      #|    - [ ] #5 Pick visual layout (p4)
      #|  - [x] #2 Design schema (p3)
      #|
    ),
  )
}

///|
test "graph json round trip" {
  let graph = sample_graph()
  let json = graph.to_json()
  let decoded : @issues.IssueGraph = try! @json.from_json(json)
  inspect(decoded == graph, content="true")
}
