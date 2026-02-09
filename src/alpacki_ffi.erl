-module(alpacki_ffi).

-export([validate_header_name/1]).

validate_header_name(Name) -> validate_header_name(Name, Name).

% TODO: handle all ASCII!
validate_header_name(<<>>, Name) -> {ok, Name};
validate_header_name(<<C, Remaining/binary>>, Name) when
  C >= $a, C =< $z;
  C >= $0, C =< $9;
  C =:= $-; C =:= $_; C =:= $.; C =:= $: ->
  validate_header_name(Remaining, Name);
validate_header_name(_, _) -> {error, nil}.
