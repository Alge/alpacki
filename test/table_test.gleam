import alpacki

// Static Table
// -----------------------------------------------------------------------------

pub fn static_lookup_first_entry_test() {
  assert alpacki.lookup_static(1) == Ok(#(<<":authority":utf8>>, <<>>))
}

pub fn static_lookup_last_entry_test() {
  assert alpacki.lookup_static(61) == Ok(#(<<"www-authenticate":utf8>>, <<>>))
}

pub fn static_lookup_invalid_index_test() {
  assert alpacki.lookup_static(0) == Error(Nil)
  assert alpacki.lookup_static(100) == Error(Nil)
}

pub fn static_match_full_test() {
  assert alpacki.match_static(<<":method":utf8>>, <<"GET":utf8>>) == alpacki.FullMatch(2)
}

pub fn static_match_name_only_test() {
  assert alpacki.match_static(<<":status":utf8>>, <<"418":utf8>>) == alpacki.NameMatch(8)
  assert alpacki.match_static(<<":status":utf8>>, <<"500":utf8>>) == alpacki.FullMatch(14)
}

pub fn static_match_not_found_test() {
  assert alpacki.match_static(<<"x-custom-header":utf8>>, <<"value":utf8>>) == alpacki.NoMatch
}

pub fn static_match_case_sensitive_test() {
  assert alpacki.match_static(<<":METHOD":utf8>>, <<"GET":utf8>>) == alpacki.NoMatch
}

pub fn static_match_empty_name_test() {
  assert alpacki.match_static(<<"":utf8>>, <<"wibble":utf8>>) == alpacki.NoMatch
}

// Dynamic Table
// -----------------------------------------------------------------------------

pub fn dynamic_new_test() {
  let table = alpacki.new_dynamic(4096)
  assert alpacki.dynamic_size(table) == 0
  assert alpacki.dynamic_max_size(table) == 4096
  assert alpacki.dynamic_length(table) == 0
}

// Entry size: "content-type" (12) + "text/html" (9) + 32 = 53
pub fn dynamic_add_and_lookup_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"content-type":utf8>>, <<"text/html":utf8>>)
  assert alpacki.dynamic_length(table) == 1
  assert alpacki.dynamic_size(table) == 53
  assert alpacki.lookup_dynamic(table, 62) == Ok(#(<<"content-type":utf8>>, <<"text/html":utf8>>))
}

pub fn dynamic_add_two_entries_ordering_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"content-type":utf8>>, <<"text/html":utf8>>)
    |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
  assert alpacki.dynamic_length(table) == 2
  assert alpacki.lookup_dynamic(table, 62) == Ok(#(<<"server":utf8>>, <<"ewe":utf8>>))
  assert alpacki.lookup_dynamic(table, 63) == Ok(#(<<"content-type":utf8>>, <<"text/html":utf8>>))
}

pub fn dynamic_lookup_out_of_range_test() {
  let table = alpacki.new_dynamic(4096) |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
  assert alpacki.lookup_dynamic(table, 61) == Error(Nil)
  assert alpacki.lookup_dynamic(table, 63) == Error(Nil)
}

// "server"+"ewe" = 41, "content-type"+"text/html" = 53. Total 94 > max 90.
pub fn dynamic_evict_oldest_test() {
  let table =
    alpacki.new_dynamic(90)
    |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
    |> alpacki.add_dynamic(<<"content-type":utf8>>, <<"text/html":utf8>>)
  assert alpacki.dynamic_length(table) == 1
  assert alpacki.dynamic_size(table) == 53
  assert alpacki.lookup_dynamic(table, 62) == Ok(#(<<"content-type":utf8>>, <<"text/html":utf8>>))
}

pub fn dynamic_add_oversized_clears_test() {
  let table =
    alpacki.new_dynamic(40)
    |> alpacki.add_dynamic(<<"via":utf8>>, <<"1.1":utf8>>)
    |> alpacki.add_dynamic(<<"content-type":utf8>>, <<"application/json":utf8>>)
  assert alpacki.dynamic_length(table) == 0
  assert alpacki.dynamic_size(table) == 0
}

// "via"+"1.1"=38, "age"+"300"=38, "server"+"ewe"=41. Total 117. Max 130.
// Adding "content-type"+"text/html" (53) needs 2 evictions to fit.
pub fn dynamic_evict_multiple_test() {
  let table =
    alpacki.new_dynamic(130)
    |> alpacki.add_dynamic(<<"via":utf8>>, <<"1.1":utf8>>)
    |> alpacki.add_dynamic(<<"age":utf8>>, <<"300":utf8>>)
    |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
    |> alpacki.add_dynamic(<<"content-type":utf8>>, <<"text/html":utf8>>)
  assert alpacki.dynamic_length(table) == 2
  assert alpacki.dynamic_size(table) == 94
  assert alpacki.lookup_dynamic(table, 62) == Ok(#(<<"content-type":utf8>>, <<"text/html":utf8>>))
  assert alpacki.lookup_dynamic(table, 63) == Ok(#(<<"server":utf8>>, <<"ewe":utf8>>))
}

pub fn dynamic_match_full_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
  assert alpacki.match_dynamic(table, <<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
    == alpacki.FullMatch(62)
}

pub fn dynamic_match_name_only_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
  assert alpacki.match_dynamic(table, <<"x-request-id":utf8>>, <<"c4d8e1f0":utf8>>)
    == alpacki.NameMatch(62)
}

pub fn dynamic_match_empty_table_test() {
  let table = alpacki.new_dynamic(4096)
  assert alpacki.match_dynamic(table, <<"server":utf8>>, <<"ewe":utf8>>) == alpacki.NoMatch
}

pub fn dynamic_match_after_eviction_test() {
  let table =
    alpacki.new_dynamic(90)
    |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
    |> alpacki.add_dynamic(<<"content-type":utf8>>, <<"text/html":utf8>>)
  assert alpacki.match_dynamic(table, <<"server":utf8>>, <<"ewe":utf8>>) == alpacki.NoMatch
}

pub fn dynamic_match_prefers_newest_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
    |> alpacki.add_dynamic(<<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
  assert alpacki.match_dynamic(table, <<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
    == alpacki.FullMatch(62)
  assert alpacki.match_dynamic(table, <<"x-request-id":utf8>>, <<"c4d8e1f0":utf8>>)
    == alpacki.NameMatch(62)
}

pub fn dynamic_resize_down_evicts_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
    |> alpacki.add_dynamic(<<"content-type":utf8>>, <<"text/html":utf8>>)
    |> alpacki.resize_dynamic(55)
  assert alpacki.dynamic_length(table) == 1
  assert alpacki.dynamic_max_size(table) == 55
  assert alpacki.lookup_dynamic(table, 62) == Ok(#(<<"content-type":utf8>>, <<"text/html":utf8>>))
}

pub fn dynamic_resize_to_zero_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
    |> alpacki.resize_dynamic(0)
  assert alpacki.dynamic_length(table) == 0
  assert alpacki.dynamic_size(table) == 0
  assert alpacki.dynamic_max_size(table) == 0
}

pub fn dynamic_resize_up_preserves_test() {
  let table =
    alpacki.new_dynamic(100)
    |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
    |> alpacki.resize_dynamic(8192)
  assert alpacki.dynamic_length(table) == 1
  assert alpacki.dynamic_size(table) == 41
  assert alpacki.dynamic_max_size(table) == 8192
  assert alpacki.lookup_dynamic(table, 62) == Ok(#(<<"server":utf8>>, <<"ewe":utf8>>))
}

pub fn dynamic_clear_preserves_max_size_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"server":utf8>>, <<"ewe":utf8>>)
    |> alpacki.clear_dynamic
  assert alpacki.dynamic_length(table) == 0
  assert alpacki.dynamic_size(table) == 0
  assert alpacki.dynamic_max_size(table) == 4096
}

// Combined lookup/match
// -----------------------------------------------------------------------------

pub fn lookup_dispatches_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
  assert alpacki.lookup(table, 1) == Ok(#(<<":authority":utf8>>, <<>>))
  assert alpacki.lookup(table, 62) == Ok(#(<<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>))
  assert alpacki.lookup(table, 63) == Error(Nil)
}

pub fn match_prefers_static_full_match_test() {
  let table = alpacki.new_dynamic(4096) |> alpacki.add_dynamic(<<":method":utf8>>, <<"GET":utf8>>)
  assert alpacki.match(table, <<":method":utf8>>, <<"GET":utf8>>) == alpacki.FullMatch(2)
}

// Static has :status NameMatch(8) for unknown values. Dynamic has :status 418
// FullMatch(62). Dynamic FullMatch should win.
pub fn match_prefers_dynamic_full_over_static_name_test() {
  let table = alpacki.new_dynamic(4096) |> alpacki.add_dynamic(<<":status":utf8>>, <<"418":utf8>>)
  assert alpacki.match(table, <<":status":utf8>>, <<"418":utf8>>) == alpacki.FullMatch(62)
}

// Both tables have name-only match for :status. Static NameMatch(8) should win.
pub fn match_prefers_static_name_over_dynamic_name_test() {
  let table = alpacki.new_dynamic(4096) |> alpacki.add_dynamic(<<":status":utf8>>, <<"418":utf8>>)
  assert alpacki.match(table, <<":status":utf8>>, <<"501":utf8>>) == alpacki.NameMatch(8)
}

pub fn match_falls_through_to_dynamic_test() {
  let table =
    alpacki.new_dynamic(4096)
    |> alpacki.add_dynamic(<<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
  assert alpacki.match(table, <<"x-request-id":utf8>>, <<"7f3a9b2e":utf8>>)
    == alpacki.FullMatch(62)
  assert alpacki.match(table, <<"x-request-id":utf8>>, <<"other":utf8>>) == alpacki.NameMatch(62)
  assert alpacki.match(table, <<"x-unknown":utf8>>, <<"val":utf8>>) == alpacki.NoMatch
}
