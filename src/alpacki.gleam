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
pub fn huffman_encode(data: BitArray) {
  huffman.encode(data, <<>>, 0)
}
