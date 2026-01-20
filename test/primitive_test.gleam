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
  assert alpacki.decode_integer(<<0b00001010:8>>, 5) == Ok(#(10, <<>>))
}

// Integer 20, encoded with a 5-bit prefix + additional bits:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | 1 | 0 | 1 | 0 | 0 |
// +---+---+---+---+---+---+---+---+
// | 0 | 1 | 0 |                   |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_within_prefix_test_with_remaining_test() {
  assert alpacki.decode_integer(<<0b00010100:8, 0b010:3>>, 5)
    == Ok(#(20, <<0b010:3>>))
}

// BitArray, that is less than 8 bits in size, with N=5:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | X | 1 | 1 | 1 | 1 |   |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_within_prefix_incomplete_test() {
  assert alpacki.decode_integer(<<0b0001111:7>>, 5) == Error(alpacki.Incomplete)
}

// Integer 16, to be encoded with a 6-bit prefix:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | X | X | 0 | 1 | 0 | 0 | 0 | 0 |
// +---+---+---+---+---+---+---+---+
pub fn encode_integer_within_prefix_test() {
  assert alpacki.encode_integer(16, 6) == <<0b00010000:8>>
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
  assert alpacki.decode_integer(<<0b00011111:8, 0b10011010:8, 0b00001010:8>>, 5)
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
      4,
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
  assert alpacki.decode_integer(<<0b00000011:8, 0b1110:5>>, 2)
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
      5,
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
  assert alpacki.encode_integer(2026, 1)
    == <<0b00000001:8, 0b11101001:8, 0b00001111:8>>
}

// Integer 42, encoded with a 8-bit prefix:
//   0   1   2   3   4   5   6   7
// +---+---+---+---+---+---+---+---+
// | 0 | 0 | 1 | 0 | 1 | 0 | 1 | 0 |
// +---+---+---+---+---+---+---+---+
pub fn decode_integer_starting_at_octet_boundary_test() {
  assert alpacki.decode_integer(<<0b00101010:8>>, 8) == Ok(#(42, <<>>))
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
      alpacki.decode_integer(<<0b11111111:8, 0b111:3>>, 9)
    })
}

// Integer 22, to be encoded with a prefix not between 1 and 8.
pub fn encode_integer_invalid_prefix_bits_test() {
  let assert Error(exception.Errored(_dynamic)) =
    exception.rescue(fn() { alpacki.encode_integer(22, -1) })
}
