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
