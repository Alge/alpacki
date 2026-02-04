import alpacki/internal/huffman
import gleam/bit_array
import gleam/result

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
      use string_literal <- result.try(huffman_decode(encoded))
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
    True -> #(huffman_encode(data), 0b10000000)
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
pub fn huffman_decode(data: BitArray) -> Result(BitArray, DecodeError) {
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
pub fn huffman_encode(data: BitArray) -> BitArray {
  huffman.encode(data, <<>>, 0)
}

// Static Table
// -----------------------------------------------------------------------------

/// Looks up a header by its index (1-61) in the static table.
pub fn static_table_lookup(index: Int) -> Result(#(String, String), Nil) {
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

/// Result of matching a header against the static table
pub type StaticTableMatch {
  /// Both name and value match exactly
  FullMatch(index: Int)
  /// Only the name matches, with index of first occurrence
  NameMatch(index: Int)
  /// Name not in static table
  NoMatch
}

/// Matches a header against the static table.
///
/// Returns:
/// - `FullMatch(index)` if both name and value match exactly
/// - `NameMatch(index)` if only the name matches
/// - `NoMatch` if the name is not in the static table
pub fn static_table_match(name: String, value: String) -> StaticTableMatch {
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
