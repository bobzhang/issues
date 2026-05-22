///|
test "issue id is stable sha title hash" {
  inspect(issue_id_from_title("Build tracker"), content="iss_21845b479070a3c5")
}

///|
test "issue title is normalized before hashing" {
  inspect(
    issue_id_from_title(normalize_title("  Build tracker  ")),
    content="iss_21845b479070a3c5",
  )
}

///|
test "markdown task parser preserves nesting and status" {
  let source =
    #|- [ ] Build tracker
    #|      - [x] Implement CLI
    #|      - [ ] Implement dashboard
    #|            - [ ] Wire Rabbit Tea controls
    #|
  let todos = markdown_todos_from_string(source)
  inspect(
    markdown_todo_summary(todos),
    content=(
      #|- Build tracker [todo]
      #|  - Implement CLI [done]
      #|  - Implement dashboard [todo]
      #|    - Wire Rabbit Tea controls [todo]
      #|
    ),
  )
}

///|
fn markdown_todo_summary(todos : Array[MarkdownTodo]) -> String {
  let buf = StringBuilder::new()
  for todo in todos {
    write_markdown_todo_summary(todo, 0, buf)
  }
  buf.to_string()
}

///|
fn write_markdown_todo_summary(
  todo : MarkdownTodo,
  depth : Int,
  buf : StringBuilder,
) -> Unit {
  for _ in 0..<depth {
    buf.write_string("  ")
  }
  buf.write_string("- \{todo.title} [\{todo.status.to_storage()}]\n")
  for child in todo.children {
    write_markdown_todo_summary(child, depth + 1, buf)
  }
}
