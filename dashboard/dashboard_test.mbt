///|
fn sample_graph() -> @issues.IssueGraph {
  {
    items: [
      {
        id: "1",
        title: "Build tracker",
        body: "Track work",
        status: Todo,
        priority: 5,
      },
      { id: "2", title: "Implement CLI", body: "", status: Todo, priority: 8 },
    ],
    edges: [{ from_id: "1", to_id: "2", kind: Contains }],
    current_id: Some("1"),
  }
}

///|
test "static render includes outline and selected item" {
  let html = @dashboard.render_static(sample_graph())
  assert_true(html.contains("Issues Dashboard"))
  assert_true(html.contains("Build tracker"))
  assert_true(html.contains("Implement CLI"))
}

///|
test "graph data decodes from exported json" {
  let graph = sample_graph()
  let decoded = @dashboard.graph_from_json_string(graph.to_json().stringify())
  inspect(decoded == graph, content="true")
}
