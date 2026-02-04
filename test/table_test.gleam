import alpacki

pub fn lookup_first_entry_test() {
  assert alpacki.static_table_lookup(1) == Ok(#(":authority", ""))
}

pub fn lookup_last_entry_test() {
  assert alpacki.static_table_lookup(61) == Ok(#("www-authenticate", ""))
}

pub fn lookup_invalid_index_test() {
  assert alpacki.static_table_lookup(0) == Error(Nil)
  assert alpacki.static_table_lookup(100) == Error(Nil)
}

pub fn match_exact_method_get_test() {
  assert alpacki.static_table_match(":method", "GET") == alpacki.FullMatch(2)
}

pub fn match_name_only_status_test() {
  // :status exists, but 418 doesn't; First occurrence of :status is index 8
  assert alpacki.static_table_match(":status", "418") == alpacki.NameMatch(8)

  // But 500 is actually in the table
  assert alpacki.static_table_match(":status", "500") == alpacki.FullMatch(14)
}

pub fn match_not_found_custom_header_test() {
  assert alpacki.static_table_match("x-custom-header", "value")
    == alpacki.NoMatch
}

pub fn match_case_sensitive_test() {
  // Headers should be lowercase, so uppercase should not match
  assert alpacki.static_table_match(":METHOD", "GET") == alpacki.NoMatch
}

pub fn match_empty_name_test() {
  assert alpacki.static_table_match("", "wibble") == alpacki.NoMatch
}
