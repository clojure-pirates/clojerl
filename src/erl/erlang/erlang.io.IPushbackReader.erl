-module('erlang.io.IPushbackReader').

-include("clojerl_int.hrl").

-clojure(true).
-protocol(true).

-export(['unread'/2]).
-export([?SATISFIES/1]).

-callback 'unread'(any(), any()) -> any().

'unread'(Reader, Ch) ->
  case clj_rt:type_module(Reader) of
    'erlang.io.PushbackReader' ->
      'erlang.io.PushbackReader':'unread'(Reader, Ch);
    Type ->
      clj_protocol:not_implemented(?MODULE, 'unread', Type)
  end.

?SATISFIES('erlang.io.PushbackReader') -> true;
?SATISFIES(_) -> false.
