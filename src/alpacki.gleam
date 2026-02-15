//// <script>
//// const docs = [
////   {
////     header: "Headers",
////     functions: [
////       "decode_header_block",
////       "encode_header_block"
////     ]
////   },
////   {
////     header: "Tables",
////     functions: [
////       "match",
////       "lookup"
////     ]
////   },
////   {
////     header: "Dynamic Table",
////     functions: [
////       "new_dynamic",
////       "add_dynamic",
////       "lookup_dynamic",
////       "match_dynamic",
////       "resize_dynamic",
////       "clear_dynamic",
////       "set_max_size"
////     ]
////   },
////   {
////     header: "Static Table",
////     functions: [
////       "lookup_static",
////       "match_static"
////     ]
////   },
////   {
////     header: "Primitives",
////     functions: [
////      "decode_integer",
////      "encode_integer",
////      "decode_string_literal",
////      "encode_string_literal"
////     ]
////   },
////   {
////     header: "Huffman",
////     functions: [
////       "decode_huffman",
////       "encode_huffman"
////     ]
////   },
//// ]
////
//// const callback = () => {
////   const list = document.querySelector(".sidebar > ul:last-of-type")
////   const sortedLists = document.createDocumentFragment()
////   const sortedMembers = document.createDocumentFragment()
////
////   for (const section of docs) {
////     sortedLists.append((() => {
////       const node = document.createElement("h3")
////       node.append(section.header)
////       return node
////     })())
////     sortedMembers.append((() => {
////       const node = document.createElement("h2")
////       node.append(section.header)
////       return node
////     })())
////
////     const sortedList = document.createElement("ul")
////     sortedLists.append(sortedList)
////
////     const sortedFunctions = [...section.functions].sort()
////
////     for (const funcName of sortedFunctions) {
////       const href = `#${funcName}`
////       const member = document.querySelector(
////         `.member:has(h2 > a[href="${href}"])`
////       )
////       const sidebar = list.querySelector(`li:has(a[href="${href}"])`)
////       sortedList.append(sidebar)
////       sortedMembers.append(member)
////     }
////   }
////
////   document.querySelector(".sidebar").insertBefore(sortedLists, list)
////   document
////     .querySelector(".module-members:has(#module-values)")
////     .insertBefore(
////       sortedMembers,
////       document.querySelector("#module-values").nextSibling
////     )
//// }
////
//// document.readyState !== "loading"
////   ? callback()
////   : document.addEventListener(
////     "DOMContentLoaded",
////     callback,
////     { once: true }
////   )
//// </script>

import alpacki/internal/huffman
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type DecodeError {
  Incomplete
  IntegerOverflow
  InvalidEncoding
}

// Primitive Type Representations
// -----------------------------------------------------------------------------

/// Decodes an integer used to represent name indexes, header field indexes,
/// or string lengths. It accepts a BitArray starting at the byte containing the
/// prefix, and the number of bits of the prefix (N). Returns either the decoded
/// integer with the remaining BitArray data, or a decode error.
///
/// The prefix size is always between 1 and 8 bits. Passing another integer will
/// cause a panic!
///
/// For more information, see Section 5.1:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-5.1
///
/// ---
///
/// An integer is represented in two parts: a prefix that fills the current
/// octet and an optional list of octets that are used if the integer value does
/// not fit within the prefix.
///
/// Example: integer value encoded within the prefix for N = 5:
/// ```
///   0   1   2   3   4   5   6   7
/// +---+---+---+---+---+---+---+---+
/// | ? | ? | ? |       Value       |
/// +---+---+---+-------------------+
/// ```
///
/// If the integer is too big to be encoded within the N-bit prefix, all the
/// bits of the prefix are set to 1, the value, decreased by 2^N-1, is encoded
/// using a list of one or more octets, and the most significant bit of each
/// octet is used as a continuation flag. The flag is set to 1 for all octets
/// except the last one in the list.
///
/// Example: integer value encoded after the prefix for N = 5:
/// ```
///   0   1   2   3   4   5   6   7
/// +---+---+---+---+---+---+---+---+
/// | ? | ? | ? | 1   1   1   1   1 |
/// +---+---+---+-------------------+
/// | 1 |    Value-(2^N-1) LSB      |
/// +---+---------------------------+
///                ...
/// +---+---------------------------+
/// | 0 |    Value-(2^N-1) MSB      |
/// +---+---------------------------+
/// ```
pub fn decode_integer(
  data: BitArray,
  prefix prefix: Int,
) -> Result(#(Int, BitArray), DecodeError) {
  let maximum_prefix = maximum_value_for_bits(prefix)
  let ignored = 8 - prefix
  case data {
    <<_ignored:size(ignored), value:size(prefix), remaining:bits>> ->
      case value == maximum_prefix {
        // Integer value encoded after the prefix.
        True -> decode_integer_after_prefix(remaining, maximum_prefix, 1)
        // Integer value encoded within the prefix.
        False -> Ok(#(value, remaining))
      }
    _ -> Error(Incomplete)
  }
}

// Maximum allowed continuation multiplier (128^4)
// Allows 4 continuation bytes * 7 bits = 28 bits + 8-bit prefix = 36 bits
// total. This is plenty for HPACK.
const max_continuation_multiplier = 268_435_456

// Decodes an integer encoded after the prefix.
fn decode_integer_after_prefix(
  data: BitArray,
  accumulated: Int,
  multiplier: Int,
  // ^^^^^^^
  // Represents the place value weight of the current continuation byte in
  // base-128 arithmetic.
) {
  // First check: "Are we about to read a 5th continuation byte?"
  case multiplier > max_continuation_multiplier, data {
    // No more than 4 continuation bytes allowed!
    True, _ -> Error(IntegerOverflow)

    // If MSB is set to 0, this is the last byte.
    False, <<0:1, value:7, remaining:bits>> ->
      Ok(#(accumulated + value * multiplier, remaining))
    // If MSB is set to 1, the value continues.
    False, <<1:1, value:7, remaining:bits>> ->
      decode_integer_after_prefix(
        remaining,
        accumulated + value * multiplier,
        multiplier * 128,
      )

    False, _ -> Error(Incomplete)
  }
}

/// Encodes an integer used to represent name indexes, header field indexes,
/// or string lengths. It accepts an integer to encode and the number of bits
/// of the prefix (N). Returns the encoded BitArray.
///
/// The prefix size is always between 1 and 8 bits. Passing another integer will
/// cause a panic!
///
/// For more information, see Section 5.1:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-5.1
///
/// ---
///
/// An integer is represented in two parts: a prefix that fills the current
/// octet and an optional list of octets that are used if the integer value does
/// not fit within the prefix.
///
/// ```
///   0   1   2   3   4   5   6   7
/// +---+---+---+---+---+---+---+---+
/// | ? | ? | ? |       Value       | N = 5
/// +---+---+---+-------------------+
/// ```
///
/// If the integer is too big to be encoded within the N-bit prefix, all the
/// bits of the prefix are set to 1, the value, decreased by 2^N-1, is encoded
/// using a list of one or more octets, and the most significant bit of each
/// octet is used as a continuation flag. The flag is set to 1 for all octets
/// except the last one in the list.
///
/// ```
///   0   1   2   3   4   5   6   7
/// +---+---+---+---+---+---+---+---+
/// | ? | ? | ? | 1   1   1   1   1 | N = 5
/// +---+---+---+-------------------+
/// | 1 |    Value-(2^N-1) LSB      |
/// +---+---------------------------+
///                ...
/// +---+---------------------------+
/// | 0 |    Value-(2^N-1) MSB      |
/// +---+---------------------------+
/// ```
pub fn encode_integer(integer: Int, prefix prefix: Int) -> BitArray {
  let maximum_prefix = maximum_value_for_bits(prefix)
  let ignored = 8 - prefix

  case integer < maximum_prefix {
    True -> <<0:size(ignored), integer:size(prefix)>>
    False ->
      encode_integer_after_prefix(integer - maximum_prefix, <<
        0:size(ignored),
        maximum_prefix:size(prefix),
      >>)
  }
}

// Encodes continuation bytes using base-128 variable-length encoding.
fn encode_integer_after_prefix(
  remaining: Int,
  accumulated: BitArray,
) -> BitArray {
  case remaining < 128 {
    True -> <<accumulated:bits, 0:1, remaining:7>>
    False ->
      encode_integer_after_prefix(remaining / 128, <<
        accumulated:bits,
        1:1,
        { remaining % 128 }:7,
      >>)
  }
}

// Maximum integer value for a particular prefix size (N for integer
// representation), calculated with: 2^N - 1. Integers outside [1, 8] will
// raise a panic!
fn maximum_value_for_bits(n: Int) -> Int {
  case n {
    8 -> 255
    7 -> 127
    6 -> 63
    5 -> 31
    4 -> 15
    3 -> 7
    2 -> 3
    1 -> 1
    _ -> panic as "Invalid HPACK prefix size!"
  }
}

/// Decodes a string literal used for header field names and values. Returns the
/// decoded octets and the remaining BitArray, or a decode error.
///
/// For more information, see Section 5.2:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-5.2
///
/// ---
///
/// String literals are opaque sequences of octets that can be encoded either
/// directly or using Huffman encoding. Its representation contains one-bit
/// flag, indicating whether or not the octets of the string are Huffman
/// encoded, the number of octets used to encode the string literal, encoded as
/// an integer with a 7-bit prefix, and encoded data of the string literal.
///
/// ```
///   0   1   2   3   4   5   6   7
/// +---+---+---+---+---+---+---+---+
/// | H |    String Length (7+)     |
/// +---+---------------------------+
/// |  String Data (Length octets)  |
/// +-------------------------------+
/// ```
pub fn decode_string_literal(
  data: BitArray,
) -> Result(#(BitArray, BitArray), DecodeError) {
  use #(length, remaining) <- result.try(decode_integer(data, 7))

  case remaining, data {
    <<encoded:bytes-size(length), remaining:bits>>, <<1:1, _remaining:bits>> -> {
      use string_literal <- result.try(decode_huffman(encoded))
      Ok(#(string_literal, remaining))
    }
    <<string_literal:bytes-size(length), remaining:bits>>,
      <<0:1, _remaining:bits>>
    -> Ok(#(string_literal, remaining))
    _, _ -> Error(Incomplete)
  }
}

/// Encodes a string literal representation for header field names and values.
/// Accepts the raw octets to encode and a flag indicating whether to use
/// Huffman encoding. Returns the encoded BitArray.
///
///
/// For more information, see Section 5.2:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-5.2
///
/// ---
///
/// String literals are opaque sequences of octets that can be encoded either
/// directly or using Huffman encoding. Its representation contains one-bit
/// flag, indicating whether or not the octets of the string are Huffman
/// encoded, the number of octets used to encode the string literal, encoded as
/// an integer with a 7-bit prefix, and encoded data of the string literal.
///
/// ```
///   0   1   2   3   4   5   6   7
/// +---+---+---+---+---+---+---+---+
/// | H |    String Length (7+)     |
/// +---+---------------------------+
/// |  String Data (Length octets)  |
/// +-------------------------------+
/// ```
pub fn encode_string_literal(data: BitArray, huffman huffman: Bool) -> BitArray {
  let #(data, h) = case huffman {
    True -> #(encode_huffman(data), 0b10000000)
    False -> #(data, 0b00000000)
  }

  case bit_array.byte_size(data) |> encode_integer(prefix: 7) {
    <<byte:8, remaining:bits>> -> <<{ byte + h }:8, remaining:bits, data:bits>>
    _ -> panic as "Unreachable pattern for encoded integer!"
  }
}

// Huffman
// -----------------------------------------------------------------------------

/// Decodes Huffman-encoded data according to RFC 7541 Appendix B.
///
/// Accepts Huffman-encoded bits and returns the decoded byte sequence. The
/// input must be properly padded to an octet boundary with valid EOS padding
/// (1-7 bits of all 1s).
///
/// For more information, see Section 5.2:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-5.2
pub fn decode_huffman(data: BitArray) -> Result(BitArray, DecodeError) {
  huffman.decode(data, <<>>)
  |> result.replace_error(InvalidEncoding)
}

/// Encodes data using Huffman encoding according to RFC 7541 Appendix B.
///
/// Accepts raw bytes and returns Huffman-encoded bits with EOS padding to align
/// to an octet boundary.
///
/// For more information, see Section 5.2:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-5.2
pub fn encode_huffman(data: BitArray) -> BitArray {
  huffman.encode(data, <<>>)
}

// Static Table
// -----------------------------------------------------------------------------

/// Looks up a header by index from 1 to 61 in the static table.
pub fn lookup_static(index: Int) -> Result(#(String, String), Nil) {
  case index {
    1 -> Ok(#(":authority", ""))
    2 -> Ok(#(":method", "GET"))
    3 -> Ok(#(":method", "POST"))
    4 -> Ok(#(":path", "/"))
    5 -> Ok(#(":path", "/index.html"))
    6 -> Ok(#(":scheme", "http"))
    7 -> Ok(#(":scheme", "https"))
    8 -> Ok(#(":status", "200"))
    9 -> Ok(#(":status", "204"))
    10 -> Ok(#(":status", "206"))
    11 -> Ok(#(":status", "304"))
    12 -> Ok(#(":status", "400"))
    13 -> Ok(#(":status", "404"))
    14 -> Ok(#(":status", "500"))
    15 -> Ok(#("accept-charset", ""))
    16 -> Ok(#("accept-encoding", "gzip, deflate"))
    17 -> Ok(#("accept-language", ""))
    18 -> Ok(#("accept-ranges", ""))
    19 -> Ok(#("accept", ""))
    20 -> Ok(#("access-control-allow-origin", ""))
    21 -> Ok(#("age", ""))
    22 -> Ok(#("allow", ""))
    23 -> Ok(#("authorization", ""))
    24 -> Ok(#("cache-control", ""))
    25 -> Ok(#("content-disposition", ""))
    26 -> Ok(#("content-encoding", ""))
    27 -> Ok(#("content-language", ""))
    28 -> Ok(#("content-length", ""))
    29 -> Ok(#("content-location", ""))
    30 -> Ok(#("content-range", ""))
    31 -> Ok(#("content-type", ""))
    32 -> Ok(#("cookie", ""))
    33 -> Ok(#("date", ""))
    34 -> Ok(#("etag", ""))
    35 -> Ok(#("expect", ""))
    36 -> Ok(#("expires", ""))
    37 -> Ok(#("from", ""))
    38 -> Ok(#("host", ""))
    39 -> Ok(#("if-match", ""))
    40 -> Ok(#("if-modified-since", ""))
    41 -> Ok(#("if-none-match", ""))
    42 -> Ok(#("if-range", ""))
    43 -> Ok(#("if-unmodified-since", ""))
    44 -> Ok(#("last-modified", ""))
    45 -> Ok(#("link", ""))
    46 -> Ok(#("location", ""))
    47 -> Ok(#("max-forwards", ""))
    48 -> Ok(#("proxy-authenticate", ""))
    49 -> Ok(#("proxy-authorization", ""))
    50 -> Ok(#("range", ""))
    51 -> Ok(#("referer", ""))
    52 -> Ok(#("refresh", ""))
    53 -> Ok(#("retry-after", ""))
    54 -> Ok(#("server", ""))
    55 -> Ok(#("set-cookie", ""))
    56 -> Ok(#("strict-transport-security", ""))
    57 -> Ok(#("transfer-encoding", ""))
    58 -> Ok(#("user-agent", ""))
    59 -> Ok(#("vary", ""))
    60 -> Ok(#("via", ""))
    61 -> Ok(#("www-authenticate", ""))
    _ -> Error(Nil)
  }
}

/// Searches the static table for an entry matching the name and value. Returns
/// FullMatch with index if both match, NameMatch with index if only name
/// matches, or NoMatch.
pub fn match_static(name: String, value: String) -> TableMatch {
  case name, value {
    ":authority", "" -> FullMatch(1)
    ":method", "GET" -> FullMatch(2)
    ":method", "POST" -> FullMatch(3)
    ":path", "/" -> FullMatch(4)
    ":path", "/index.html" -> FullMatch(5)
    ":scheme", "http" -> FullMatch(6)
    ":scheme", "https" -> FullMatch(7)
    ":status", "200" -> FullMatch(8)
    ":status", "204" -> FullMatch(9)
    ":status", "206" -> FullMatch(10)
    ":status", "304" -> FullMatch(11)
    ":status", "400" -> FullMatch(12)
    ":status", "404" -> FullMatch(13)
    ":status", "500" -> FullMatch(14)
    "accept-charset", "" -> FullMatch(15)
    "accept-encoding", "gzip, deflate" -> FullMatch(16)
    "accept-language", "" -> FullMatch(17)
    "accept-ranges", "" -> FullMatch(18)
    "accept", "" -> FullMatch(19)
    "access-control-allow-origin", "" -> FullMatch(20)
    "age", "" -> FullMatch(21)
    "allow", "" -> FullMatch(22)
    "authorization", "" -> FullMatch(23)
    "cache-control", "" -> FullMatch(24)
    "content-disposition", "" -> FullMatch(25)
    "content-encoding", "" -> FullMatch(26)
    "content-language", "" -> FullMatch(27)
    "content-length", "" -> FullMatch(28)
    "content-location", "" -> FullMatch(29)
    "content-range", "" -> FullMatch(30)
    "content-type", "" -> FullMatch(31)
    "cookie", "" -> FullMatch(32)
    "date", "" -> FullMatch(33)
    "etag", "" -> FullMatch(34)
    "expect", "" -> FullMatch(35)
    "expires", "" -> FullMatch(36)
    "from", "" -> FullMatch(37)
    "host", "" -> FullMatch(38)
    "if-match", "" -> FullMatch(39)
    "if-modified-since", "" -> FullMatch(40)
    "if-none-match", "" -> FullMatch(41)
    "if-range", "" -> FullMatch(42)
    "if-unmodified-since", "" -> FullMatch(43)
    "last-modified", "" -> FullMatch(44)
    "link", "" -> FullMatch(45)
    "location", "" -> FullMatch(46)
    "max-forwards", "" -> FullMatch(47)
    "proxy-authenticate", "" -> FullMatch(48)
    "proxy-authorization", "" -> FullMatch(49)
    "range", "" -> FullMatch(50)
    "referer", "" -> FullMatch(51)
    "refresh", "" -> FullMatch(52)
    "retry-after", "" -> FullMatch(53)
    "server", "" -> FullMatch(54)
    "set-cookie", "" -> FullMatch(55)
    "strict-transport-security", "" -> FullMatch(56)
    "transfer-encoding", "" -> FullMatch(57)
    "user-agent", "" -> FullMatch(58)
    "vary", "" -> FullMatch(59)
    "via", "" -> FullMatch(60)
    "www-authenticate", "" -> FullMatch(61)
    ":authority", _ -> NameMatch(1)
    ":method", _ -> NameMatch(2)
    ":path", _ -> NameMatch(4)
    ":scheme", _ -> NameMatch(6)
    ":status", _ -> NameMatch(8)
    "accept-charset", _ -> NameMatch(15)
    "accept-encoding", _ -> NameMatch(16)
    "accept-language", _ -> NameMatch(17)
    "accept-ranges", _ -> NameMatch(18)
    "accept", _ -> NameMatch(19)
    "access-control-allow-origin", _ -> NameMatch(20)
    "age", _ -> NameMatch(21)
    "allow", _ -> NameMatch(22)
    "authorization", _ -> NameMatch(23)
    "cache-control", _ -> NameMatch(24)
    "content-disposition", _ -> NameMatch(25)
    "content-encoding", _ -> NameMatch(26)
    "content-language", _ -> NameMatch(27)
    "content-length", _ -> NameMatch(28)
    "content-location", _ -> NameMatch(29)
    "content-range", _ -> NameMatch(30)
    "content-type", _ -> NameMatch(31)
    "cookie", _ -> NameMatch(32)
    "date", _ -> NameMatch(33)
    "etag", _ -> NameMatch(34)
    "expect", _ -> NameMatch(35)
    "expires", _ -> NameMatch(36)
    "from", _ -> NameMatch(37)
    "host", _ -> NameMatch(38)
    "if-match", _ -> NameMatch(39)
    "if-modified-since", _ -> NameMatch(40)
    "if-none-match", _ -> NameMatch(41)
    "if-range", _ -> NameMatch(42)
    "if-unmodified-since", _ -> NameMatch(43)
    "last-modified", _ -> NameMatch(44)
    "link", _ -> NameMatch(45)
    "location", _ -> NameMatch(46)
    "max-forwards", _ -> NameMatch(47)
    "proxy-authenticate", _ -> NameMatch(48)
    "proxy-authorization", _ -> NameMatch(49)
    "range", _ -> NameMatch(50)
    "referer", _ -> NameMatch(51)
    "refresh", _ -> NameMatch(52)
    "retry-after", _ -> NameMatch(53)
    "server", _ -> NameMatch(54)
    "set-cookie", _ -> NameMatch(55)
    "strict-transport-security", _ -> NameMatch(56)
    "transfer-encoding", _ -> NameMatch(57)
    "user-agent", _ -> NameMatch(58)
    "vary", _ -> NameMatch(59)
    "via", _ -> NameMatch(60)
    "www-authenticate", _ -> NameMatch(61)
    _, _ -> NoMatch
  }
}

// Dynamic Table
// -----------------------------------------------------------------------------

/// Dynamic table for HPACK compression. Stores recently used headers with
/// indices starting at 62. The encoder and decoder each maintain their own
/// table.
///
/// See RFC 7541 Section 2.3:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-2.3
pub opaque type DynamicTable {
  DynamicTable(
    entries: List(#(String, String)),
    size: Int,
    max_size: Int,
    length: Int,
    pending_resize: Option(Int),
  )
}

// Dynamic table starts at index 62.
const dynamic_table_start = 62

// Entry overhead as defined in RFC 7541 Section 4.1.
const entry_overhead = 32

/// Creates an empty dynamic table with the specified maximum size in bytes.
/// Default maximum size per RFC 7541 is 4096 bytes.
pub fn new_dynamic(max_size: Int) -> DynamicTable {
  DynamicTable(entries: [], size: 0, max_size:, length: 0, pending_resize: None)
}

/// Adds an entry to the dynamic table at index 62. Evicts oldest entries if
/// the new entry would exceed maximum size. Clears the table without adding if
/// the entry alone exceeds maximum size. See RFC 7541 Section 4.4.
pub fn add_dynamic(
  table: DynamicTable,
  name: String,
  value: String,
) -> DynamicTable {
  let entry_size = calculate_entry_size(name, value)

  case entry_size > table.max_size {
    True -> DynamicTable(..table, entries: [], size: 0, length: 0)
    False -> {
      let table = evict_until_fits(table, entry_size)
      DynamicTable(
        ..table,
        entries: [#(name, value), ..table.entries],
        size: table.size + entry_size,
        length: table.length + 1,
      )
    }
  }
}

/// Looks up an entry by index in the dynamic table. Returns the name-value
/// pair or an error if the index is invalid.
pub fn lookup_dynamic(
  table: DynamicTable,
  index: Int,
) -> Result(#(String, String), Nil) {
  case index < dynamic_table_start {
    True -> Error(Nil)
    False -> {
      let position = index - dynamic_table_start
      case position < table.length {
        True -> list.drop(table.entries, position) |> list.first
        False -> Error(Nil)
      }
    }
  }
}

/// Searches the dynamic table for an entry matching the name and value. Returns
/// FullMatch with index if both match, NameMatch with index if only name
/// matches, or NoMatch.
pub fn match_dynamic(
  table: DynamicTable,
  name: String,
  value: String,
) -> TableMatch {
  case table.length {
    0 -> NoMatch
    _ -> do_match_dynamic(table.entries, name, value, 0, NoMatch)
  }
}

fn do_match_dynamic(
  entries: List(#(String, String)),
  name: String,
  value: String,
  position: Int,
  match_accumulator: TableMatch,
) -> TableMatch {
  case entries {
    // Found exact match
    [#(n, v), ..] if n == name && v == value ->
      FullMatch(dynamic_table_start + position)

    // Name matches but value doesn't
    [#(n, _), ..remaining] if n == name -> {
      let match_accumulator = case match_accumulator {
        NoMatch -> NameMatch(dynamic_table_start + position)
        match_accumulator -> match_accumulator
      }
      do_match_dynamic(remaining, name, value, position + 1, match_accumulator)
    }

    // No match
    [_, ..remaining] ->
      do_match_dynamic(remaining, name, value, position + 1, match_accumulator)

    // Return what we found
    [] -> match_accumulator
  }
}

/// Updates the dynamic table maximum size. Evicts oldest entries if current
/// size exceeds the new maximum.
pub fn resize_dynamic(table: DynamicTable, new_max_size: Int) -> DynamicTable {
  DynamicTable(..evict_to_size(table, new_max_size), max_size: new_max_size)
}

/// Removes all entries from the dynamic table while preserving maximum size.
pub fn clear_dynamic(table: DynamicTable) -> DynamicTable {
  DynamicTable(..table, entries: [], size: 0, length: 0)
}

/// Sets the maximum size of the dynamic table, typically in response to a
/// SETTINGS frame. Records the pending resize so that encode_header_block
/// automatically emits the required size update instructions at the start of
/// the next header block (RFC 7541 Section 4.2).
pub fn set_max_size(
  table: DynamicTable,
  new_max_size: Int,
) -> DynamicTable {
  let pending = case table.pending_resize {
    None -> new_max_size
    Some(current_min) -> int.min(current_min, new_max_size)
  }
  DynamicTable(
    ..evict_to_size(table, new_max_size),
    max_size: new_max_size,
    pending_resize: Some(pending),
  )
}

// Evicts oldest entries until there is space for the new entry.
fn evict_until_fits(table: DynamicTable, needed_space: Int) -> DynamicTable {
  case table.size + needed_space <= table.max_size {
    True -> table
    False -> {
      let #(reversed_entries, new_size, new_length) =
        do_evict_until_fits(
          list.reverse(table.entries),
          table.size,
          table.length,
          needed_space,
          table.max_size,
        )

      DynamicTable(
        ..table,
        entries: list.reverse(reversed_entries),
        size: new_size,
        length: new_length,
      )
    }
  }
}

fn do_evict_until_fits(
  reversed_entries: List(#(String, String)),
  size: Int,
  length: Int,
  needed_space: Int,
  max_size: Int,
) -> #(List(#(String, String)), Int, Int) {
  case size + needed_space <= max_size {
    True -> #(reversed_entries, size, length)
    False ->
      case reversed_entries {
        [] -> #([], size, length)
        [#(name, value), ..rest] -> {
          let freed_size = calculate_entry_size(name, value)

          do_evict_until_fits(
            rest,
            size - freed_size,
            length - 1,
            needed_space,
            max_size,
          )
        }
      }
  }
}

// Evicts oldest entries until table size is within the target size.
fn evict_to_size(table: DynamicTable, target_size: Int) -> DynamicTable {
  case table.size <= target_size {
    True -> table
    False -> {
      let #(reversed_entries, new_size, new_length) =
        do_evict_to_size(
          list.reverse(table.entries),
          table.size,
          table.length,
          target_size,
        )

      DynamicTable(
        ..table,
        entries: list.reverse(reversed_entries),
        size: new_size,
        length: new_length,
      )
    }
  }
}

fn do_evict_to_size(
  reversed_entries: List(#(String, String)),
  size: Int,
  length: Int,
  target_size: Int,
) -> #(List(#(String, String)), Int, Int) {
  case size <= target_size {
    True -> #(reversed_entries, size, length)
    False ->
      case reversed_entries {
        [] -> #([], size, length)
        [#(name, value), ..rest] -> {
          let freed_size = calculate_entry_size(name, value)
          do_evict_to_size(rest, size - freed_size, length - 1, target_size)
        }
      }
  }
}

// Calculates entry size per RFC 7541 Section 4.1: name + value + 32 bytes.
fn calculate_entry_size(name: String, value: String) -> Int {
  string.byte_size(name) + string.byte_size(value) + entry_overhead
}

// Tables
// -----------------------------------------------------------------------------

/// Result of matching a header against a table.
pub type TableMatch {
  FullMatch(index: Int)
  NameMatch(index: Int)
  NoMatch
}

/// Searches static and dynamic tables for an entry matching the name and value.
/// Returns FullMatch with index if both match, NameMatch with index if only
/// name matches, or NoMatch.
pub fn match(
  name: String,
  value: String,
  dynamic_table: DynamicTable,
) -> TableMatch {
  case match_static(name, value) {
    NameMatch(static_index) -> {
      case match_dynamic(dynamic_table, name, value) {
        NoMatch | NameMatch(_) -> NameMatch(static_index)
        matched -> matched
      }
    }
    NoMatch -> match_dynamic(dynamic_table, name, value)
    full_match -> full_match
  }
}

/// Looks up an entry by index in the static table or dynamic table. Returns
/// the name-value pair or an error if the index is invalid.
pub fn lookup(
  index: Int,
  dynamic_table: DynamicTable,
) -> Result(#(String, String), Nil) {
  case index < dynamic_table_start {
    True -> lookup_static(index)
    False -> lookup_dynamic(dynamic_table, index)
  }
}

// Headers
// -----------------------------------------------------------------------------

/// Indexing mode for a header field, controlling how the encoder represents it
/// on the wire and how the decoder preserves the original signal.
pub type Indexing {
  /// 6.2.1 — Store in the dynamic table for future reference.
  WithIndexing
  /// 6.2.2 — Do not store. Useful for headers that change every request.
  WithoutIndexing
  /// 6.2.3 — Do not store, and signal to intermediaries that this value is
  /// sensitive and must never be compressed. Intermediaries MUST preserve this
  /// representation (RFC 7541 Section 7.1.3).
  NeverIndexed
}

pub type HeaderField {
  HeaderField(name: String, value: String, indexing: Indexing)
}

/// Decodes a complete header block fragment into a list of header fields,
/// updating the dynamic table as specified by the encoded instructions.
///
/// For more information, see Section 6:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-6
pub fn decode_header_block(
  data: BitArray,
  dynamic_table: DynamicTable,
) -> Result(#(List(HeaderField), DynamicTable), DecodeError) {
  decode_header_fields(data, dynamic_table, [])
}

fn decode_header_fields(
  data: BitArray,
  table: DynamicTable,
  acc: List(HeaderField),
) -> Result(#(List(HeaderField), DynamicTable), DecodeError) {
  case data {
    <<>> -> Ok(#(list.reverse(acc), table))

    // 6.1 Indexed Header Field Representation
    //   0   1   2   3   4   5   6   7
    // +---+---+---+---+---+---+---+---+
    // | 1 |        Index (7+)         |
    // +---+---------------------------+
    <<1:1, _:7, _:bits>> -> {
      use #(index, remaining) <- result.try(decode_integer(data, 7))
      use #(name, value) <- result.try(
        lookup(index, table) |> result.replace_error(InvalidEncoding),
      )
      let header = HeaderField(name:, value:, indexing: WithIndexing)
      decode_header_fields(remaining, table, [header, ..acc])
    }

    // 6.2.1 Literal Header Field with Incremental Indexing
    //   0   1   2   3   4   5   6   7
    // +---+---+---+---+---+---+---+---+
    // | 0 | 1 |      Index (6+)       |
    // +---+---+-----------------------+
    <<0:1, 1:1, _:6, _:bits>> -> {
      use #(name, value, remaining) <- result.try(decode_literal(data, table, 6))
      let table = add_dynamic(table, name, value)
      let header = HeaderField(name:, value:, indexing: WithIndexing)
      decode_header_fields(remaining, table, [header, ..acc])
    }

    // 6.3 Dynamic Table Size Update
    //   0   1   2   3   4   5   6   7
    // +---+---+---+---+---+---+---+---+
    // | 0 | 0 | 1 |   Max size (5+)   |
    // +---+---+---+-------------------+
    <<0:2, 1:1, _:5, _:bits>> -> {
      use #(new_size, remaining) <- result.try(decode_integer(data, 5))
      let table = resize_dynamic(table, new_size)
      decode_header_fields(remaining, table, acc)
    }

    // 6.2.3 Literal Header Field Never Indexed
    //   0   1   2   3   4   5   6   7
    // +---+---+---+---+---+---+---+---+
    // | 0 | 0 | 0 | 1 |  Index (4+)   |
    // +---+---+---+---+---------------+
    <<0:3, 1:1, _:4, _:bits>> -> {
      use #(name, value, remaining) <- result.try(decode_literal(data, table, 4))
      let header = HeaderField(name:, value:, indexing: NeverIndexed)
      decode_header_fields(remaining, table, [header, ..acc])
    }

    // 6.2.2 Literal Header Field without Indexing
    //   0   1   2   3   4   5   6   7
    // +---+---+---+---+---+---+---+---+
    // | 0 | 0 | 0 | 0 |  Index (4+)   |
    // +---+---+---+---+---------------+
    <<0:4, _:4, _:bits>> -> {
      use #(name, value, remaining) <- result.try(decode_literal(data, table, 4))
      let header = HeaderField(name:, value:, indexing: WithoutIndexing)
      decode_header_fields(remaining, table, [header, ..acc])
    }

    _ -> Error(InvalidEncoding)
  }
}

fn decode_literal(
  data: BitArray,
  table: DynamicTable,
  prefix: Int,
) -> Result(#(String, String, BitArray), DecodeError) {
  use #(index, remaining) <- result.try(decode_integer(data, prefix))

  use #(name, remaining) <- result.try(case index {
    // That is a new string literal.
    0 -> {
      use #(name, remaining) <- result.try(decode_string_literal(remaining))
      use name <- result.try(
        validate_header_name(name)
        |> result.replace_error(InvalidEncoding),
      )

      Ok(#(name, remaining))
    }
    // That is a name from the table.
    _ -> {
      use #(name, _value) <- result.try(
        lookup(index, table) |> result.replace_error(InvalidEncoding),
      )
      Ok(#(name, remaining))
    }
  })

  use #(value, remaining) <- result.try(decode_string_literal(remaining))
  use value <- result.try(
    bit_array.to_string(value) |> result.replace_error(InvalidEncoding),
  )

  Ok(#(name, value, remaining))
}

@external(erlang, "alpacki_ffi", "validate_header_name")
fn validate_header_name(data: BitArray) -> Result(String, Nil)

/// Encodes a list of header fields into a header block fragment, updating the
/// dynamic table as headers are added.
///
/// For more information, see Section 6:
/// - https://datatracker.ietf.org/doc/html/rfc7541#section-6
pub fn encode_header_block(
  headers: List(HeaderField),
  dynamic_table: DynamicTable,
  huffman huffman: Bool,
) -> #(BitArray, DynamicTable) {
  let #(table, acc) = emit_pending_resizes(dynamic_table)
  encode_header_fields(headers, table, huffman, acc)
}

fn emit_pending_resizes(table: DynamicTable) -> #(DynamicTable, BitArray) {
  case table.pending_resize {
    None -> #(table, <<>>)
    Some(min_size) -> {
      let table = DynamicTable(..table, pending_resize: None)
      case min_size < table.max_size {
        // Size went down then back up; emit minimum then final.
        True -> {
          let first = encode_table_size_update(min_size)
          let second = encode_table_size_update(table.max_size)
          #(table, <<first:bits, second:bits>>)
        }
        // Size only went down or stayed unchanged; emit final.
        False -> #(table, encode_table_size_update(min_size))
      }
    }
  }
}

fn encode_header_fields(
  headers: List(HeaderField),
  table: DynamicTable,
  huffman: Bool,
  acc: BitArray,
) -> #(BitArray, DynamicTable) {
  case headers {
    [] -> #(acc, table)
    [header, ..rest] -> {
      let #(encoded, table) = encode_header_field(header, table, huffman)
      encode_header_fields(rest, table, huffman, <<acc:bits, encoded:bits>>)
    }
  }
}

fn encode_header_field(
  header: HeaderField,
  table: DynamicTable,
  huffman: Bool,
) -> #(BitArray, DynamicTable) {
  case match(header.name, header.value, table), header.indexing {
    // Full match; always use indexed representation (hpax approach).
    FullMatch(index), _ -> #(encode_indexed(index), table)

    // Name match + store; literal with incremental indexing.
    NameMatch(index), WithIndexing -> {
      let encoded = encode_literal(index, header.value, 6, 0x40, huffman)
      #(encoded, add_dynamic(table, header.name, header.value))
    }

    // Name match + don't store; literal without indexing.
    NameMatch(index), WithoutIndexing -> #(
      encode_literal(index, header.value, 4, 0x00, huffman),
      table,
    )

    // Name match + sensitive; literal never indexed.
    NameMatch(index), NeverIndexed -> #(
      encode_literal(index, header.value, 4, 0x10, huffman),
      table,
    )

    // No match + store; literal with incremental indexing, new name.
    NoMatch, WithIndexing -> {
      let encoded =
        encode_literal_new_name(header.name, header.value, 6, 0x40, huffman)
      #(encoded, add_dynamic(table, header.name, header.value))
    }

    // No match + don't store; literal without indexing, new name.
    NoMatch, WithoutIndexing -> #(
      encode_literal_new_name(header.name, header.value, 4, 0x00, huffman),
      table,
    )

    // No match + sensitive; literal never indexed, new name.
    NoMatch, NeverIndexed -> #(
      encode_literal_new_name(header.name, header.value, 4, 0x10, huffman),
      table,
    )
  }
}

// Encodes an integer with type bits set in the upper bits of the first byte.
fn encode_prefixed_integer(
  integer: Int,
  prefix: Int,
  type_bits: Int,
) -> BitArray {
  case encode_integer(integer, prefix:) {
    <<byte:8, remaining:bits>> -> <<{ byte + type_bits }:8, remaining:bits>>
    _ -> panic as "Unreachable pattern for encoded integer!"
  }
}

// 6.1 Indexed Header Field Representation.
fn encode_indexed(index: Int) -> BitArray {
  encode_prefixed_integer(index, 7, 0x80)
}

// 6.2.x Literal Header Field with name referenced by index.
fn encode_literal(
  index: Int,
  value: String,
  prefix: Int,
  type_bits: Int,
  huffman: Bool,
) -> BitArray {
  let index = encode_prefixed_integer(index, prefix, type_bits)
  let value = encode_string_literal(<<value:utf8>>, huffman:)
  <<index:bits, value:bits>>
}

// 6.2.x Literal Header Field with new name (index 0).
fn encode_literal_new_name(
  name: String,
  value: String,
  prefix: Int,
  type_bits: Int,
  huffman: Bool,
) -> BitArray {
  let index = encode_prefixed_integer(0, prefix, type_bits)
  let name = encode_string_literal(<<name:utf8>>, huffman:)
  let value = encode_string_literal(<<value:utf8>>, huffman:)
  <<index:bits, name:bits, value:bits>>
}

// Encodes a dynamic table size update instruction (Section 6.3).
fn encode_table_size_update(new_size: Int) -> BitArray {
  encode_prefixed_integer(new_size, 5, 0x20)
}
