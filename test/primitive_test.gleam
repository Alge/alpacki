import alpacki
import exception

// Integer Representation
// -----------------------------------------------------------------------------

// Integer 10, encoded with a 5-bit prefix:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | 0 | 1 | 0 | 1 | 0 |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_within_prefix_test() {
  assert alpacki.decode_integer(<<0b00001010:8>>, prefix: 5) == Ok(#(10, <<>>))
}

// Integer 20, encoded with a 5-bit prefix + additional bits:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | 1 | 0 | 1 | 0 | 0 |
// +---+---+---+---+---+---+---+---+
// | 0 | 1 | 0 |                   |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_within_prefix_test_with_remaining_test() {
  assert alpacki.decode_integer(<<0b00010100:8, 0b010:3>>, prefix: 5)
    == Ok(#(20, <<0b010:3>>))
}

// BitArray, that is less than 8 bits in size, with N=5:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | 1 | 1 | 1 | 1 |   |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_within_prefix_incomplete_test() {
  assert alpacki.decode_integer(<<0b0001111:7>>, prefix: 5)
    == Error(alpacki.Incomplete)
}

// Integer 16, to be encoded with a 6-bit prefix:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | 0 | 1 | 0 | 0 | 0 | 0 |
// +---+---+---+---+---+---+---+---+
pub fn encode_integer_within_prefix_test() {
  assert alpacki.encode_integer(16, prefix: 6) == <<0b00010000:8>>
}

// Integer 1337, encoded with a 5-bit prefix:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | 1 | 1 | 1 | 1 | 1 |
// +---+---+---+---+---+---+---+---+
// | 1 | 0 | 0 | 1 | 1 | 0 | 1 | 0 |
// +---+---+---+---+---+---+---+---+
// | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0 |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_after_prefix_test() {
  assert alpacki.decode_integer(
      <<0b00011111:8, 0b10011010:8, 0b00001010:8>>,
      prefix: 5,
    )
    == Ok(#(1337, <<>>))
}

// Integer 1530, encoded with a 4-bit prefix + additional bits:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | X | 1 | 1 | 1 | 1 |
// +---+---+---+---+---+---+---+---+
// | 1 | 1 | 1 | 0 | 1 | 0 | 1 | 1 |
// +---+---+---+---+---+---+---+---+
// | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 1 |
// +---+---+---+---+---+---+---+---+
// | 1 | 1 | 0 | 0 | 1 |           |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_after_prefix_test_with_remaining_test() {
  assert alpacki.decode_integer(
      <<0b00001111:8, 0b11101011:8, 0b00001011:8, 0b11001:5>>,
      prefix: 4,
    )
    == Ok(#(1530, <<0b11001:5>>))
}

// BitArray, that is more than 8 bits in size, with N=2 and all prefix bits set
// to 1:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | X | X | X | 1 | 1 |
// +---+---+---+---+---+---+---+---+
// | 1 | 1 | 1 | 0 |               |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_after_prefix_incomplete_test() {
  assert alpacki.decode_integer(<<0b00000011:8, 0b1110:5>>, prefix: 2)
    == Error(alpacki.Incomplete)
}

// Integer, encoded with 5-bit prefix, that includes more than 4 continuation
// bytes (34_359_738_399):
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | 1 | 1 | 1 | 1 | 1 | #1
// +---+---+---+---+---+---+---+---+
// | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | #2
// +---+---+---+---+---+---+---+---+
// | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | #3
// +---+---+---+---+---+---+---+---+
// | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | #4
// +---+---+---+---+---+---+---+---+
// | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | #5!
// +---+---+---+---+---+---+---+---+
// | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | #6!
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_after_prefix_overflow_test() {
  assert alpacki.decode_integer(
      <<
        0b00011111:8,
        0b10000000:8,
        0b10000000:8,
        0b10000000:8,
        0b10000000:8,
        0b10000001:8,
      >>,
      prefix: 5,
    )
    == Error(alpacki.IntegerOverflow)
}

// Integer 2026, to be encoded with a 1-bit prefix:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | X | X | X | X | 1 |
// +---+---+---+---+---+---+---+---+
// | 1 | 1 | 1 | 0 | 1 | 0 | 0 | 1 |
// +---+---+---+---+---+---+---+---+
// | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 1 |
// +---+---+---+---+---+---+---+---+
pub fn encode_integer_after_prefix_test() {
  assert alpacki.encode_integer(2026, prefix: 1)
    == <<0b00000001:8, 0b11101001:8, 0b00001111:8>>
}

// Integer 42, encoded with a 8-bit prefix:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | 0 | 0 | 1 | 0 | 1 | 0 | 1 | 0 |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_starting_at_octet_boundary_test() {
  assert alpacki.decode_integer(<<0b00101010:8>>, prefix: 8) == Ok(#(42, <<>>))
}

// BitArray, that is 8+ bits in size, with a prefix not between 1 and 8:
//   0   1   2   3   4   5   6   7   [?]
// +---+---+---+---+---+---+---+---+
// | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | [?]
// +---+---+---+---+---+---+---+---+
// | 1 | 1 | 1 |                   |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_invalid_prefix_bits_test() {
  let assert Error(exception.Errored(_dynamic)) =
    exception.rescue(fn() {
      alpacki.decode_integer(<<0b11111111:8, 0b111:3>>, prefix: 9)
    })
}

// Integer 22, to be encoded with a prefix not between 1 and 8.
pub fn encode_integer_invalid_prefix_bits_test() {
  let assert Error(exception.Errored(_dynamic)) =
    exception.rescue(fn() { alpacki.encode_integer(22, prefix: -1) })
}

// String Literal Representation
// -----------------------------------------------------------------------------

// String `hello` encoded as plain text:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 |  H=0, Length=5
// +---+---------------------------+
// |              `h`              |
// +-------------------------------+
//                ...
// +-------------------------------+
// |              `o`              |
// +-------------------------------+
pub fn decode_string_literal_plain_test() {
  assert alpacki.decode_string_literal(<<0:1, 5:7, "hello":utf8>>)
    == Ok(#(<<"hello":utf8>>, <<>>))
}

// String `wibble wobble` with 4 remaining bits.
pub fn decode_string_literal_plain_with_remaining_test() {
  assert alpacki.decode_string_literal(<<
      0:1,
      13:7,
      "wibble wobble":utf8,
      0b1010:4,
    >>)
    == Ok(#(<<"wibble wobble":utf8>>, <<0b1010:4>>))
}

// String `foo bar` to be encoded as plain string.
pub fn encode_string_literal_plain_test() {
  assert alpacki.encode_string_literal(<<"foo bar":utf8>>, huffman: False)
    == <<0:1, 7:7, "foo bar":utf8>>
}

// String `hi` Huffman-encoded:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |  H=1, Length=2
// +---+---------------------------+
// |             0x9C              |
// +-------------------------------+
// |             0xDF              |
// +-------------------------------+
pub fn decode_string_literal_huffman_test() {
  assert alpacki.decode_string_literal(<<0b10000010:8, 0x9C:8, 0xDF:8>>)
  == Ok(#(<<"hi":utf8>>, <<>>))
}
