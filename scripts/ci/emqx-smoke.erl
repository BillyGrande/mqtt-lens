%% EMQX smoke test, run with: emqx eval "$(cat emqx-smoke.erl)"
%% This code runs inside the broker node: never call halt/1 here. On failure it prints
%% a SMOKE_* marker and returns an error value; integration.sh turns that into a
%% non-zero exit.
%% Subscribes to a topic in the broker, publishes one message, and waits for delivery.
Topic = <<"smoke/test">>,
emqx:subscribe(Topic),
emqx:publish(emqx_message:make(<<"smoke-client">>, Topic, <<"hello">>)),
receive
  {deliver, Topic, Msg} ->
    case emqx_message:payload(Msg) of
      <<"hello">> -> io:format("SMOKE_OK~n");
      Other -> io:format("SMOKE_BAD_PAYLOAD ~p~n", [Other]), {error, smoke_bad_payload}
    end
after 5000 ->
  io:format("SMOKE_TIMEOUT~n"), {error, smoke_timeout}
end.
