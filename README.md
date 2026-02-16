# 🦙 alpacki

[![Package Version](https://img.shields.io/hexpm/v/alpacki)](https://hex.pm/packages/alpacki)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/alpacki/)

alpacki is an HPACK ([RFC 7541](https://datatracker.ietf.org/doc/html/rfc7541))
implementation for Gleam. It handles header compression for HTTP/2 connections.

```sh
gleam add alpacki@1
```

# Encoding and decoding

Each side of an HTTP/2 connection maintains its own dynamic table. Headers are
encoded into compact header block fragments for transmission, and decoded back
on the receiving side.

Encoding from a list of headers:
```gleam
// Encoding from a list of headers.
let table = alpacki.new_dynamic(4096)
let headers = [
  alpacki.HeaderField(":method", "GET", alpacki.WithIndexing),
  alpacki.HeaderField(":path", "/", alpacki.WithIndexing),
  alpacki.HeaderField(":scheme", "https", alpacki.WithIndexing),
]

let #(data, table) =
  alpacki.encode_header_block(headers, table, huffman: True)
```

Decoding headers from raw bits:
```gleam
let table = alpacki.new_dynamic(4096)
let assert Ok(#(headers, table)) = alpacki.decode_header_block(data, table)
```

The `Indexing` type on each `HeaderField` controls the wire representation:
`WithIndexing` adds the entry to the dynamic table for future reference,
`WithoutIndexing` sends it without storing, and `NeverIndexed` signals that
the value is sensitive and must never be compressed by intermediaries.

# Primitives

Beyond the high-level API, alpacki exposes the individual HPACK primitives.

Integer:
```gleam
let encoded = alpacki.encode_integer(120, prefix: 5)
let assert Ok(#(120, <<>>)) = alpacki.decode_integer(encoded, prefix: 5)
```

String Literal:
```gleam
let encoded = alpacki.encode_string_literal(<<"Wibble":utf8>>, huffman: False)
let assert Ok(#(decoded, <<>>)) = alpacki.decode_string_literal(encoded)
```

Huffman:
```gleam
let encoded = alpacki.encode_huffman(<<"www.example.com":utf8>>)
let assert Ok(decoded) = alpacki.decode_huffman(encoded)
```

Further documentation can be found at <https://hexdocs.pm/alpacki>.
