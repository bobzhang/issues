///|
#cfg(target="js")
extern "js" fn bootstrap_json() -> String = "() => JSON.stringify(globalThis.__ISSUES_DATA__ || { items: [], edges: [], current_id: null })"

///|
#cfg(target="js")
fn main {
  let graph = @dashboard.graph_from_json_string(bootstrap_json()) catch {
    _ => @issues.IssueGraph::empty()
  }
  @rabbita.new(@dashboard.app(graph)).mount("app")
}
