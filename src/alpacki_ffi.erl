-module(alpacki_ffi).

-export([validate_header_name/1]).

validate_header_name(<<>>) ->
  {error, nil};
% Allowed Pseudo-Headers.
validate_header_name(<<":method">>) ->
  {ok, <<":method">>};
validate_header_name(<<":path">>) ->
  {ok, <<":path">>};
validate_header_name(<<":scheme">>) ->
  {ok, <<":scheme">>};
validate_header_name(<<":status">>) ->
  {ok, <<":status">>};
validate_header_name(<<":authority">>) ->
  {ok, <<":authority">>};
validate_header_name(<<$:, _/binary>>) ->
  {error, nil};
% Per RFC (9110 Section 5.6.2 tchar + 9113 Section 8.2.1 mentioning lowercase
% ASCII) the valid bytes are:
% - a-z
% - 0-9
% - ! # $ % & ' * + - . ^ _  | ~ `
% See:
% - https://datatracker.ietf.org/doc/html/rfc9110#section-5.6.2
% - https://datatracker.ietf.org/doc/html/rfc9113#section-8.2.1
validate_header_name(Name) ->
  validate_tchar(Name, Name).

validate_tchar(<<>>, Name) ->
  {ok, Name};
validate_tchar(<<C, Remaining/binary>>, Name)
  when C >= $a andalso C =< $z;
       C >= $0 andalso C =< $9;
       C =:= $!;
       C =:= $#;
       C =:= $$;
       C =:= $%;
       C =:= $&;
       C =:= $';
       C =:= $*;
       C =:= $+;
       C =:= $-;
       C =:= $.;
       C =:= $^;
       C =:= $_;
       C =:= $`;
       C =:= $|;
       C =:= $~ ->
  validate_tchar(Remaining, Name);
validate_tchar(_, _) ->
  {error, nil}.
