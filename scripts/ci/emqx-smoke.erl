%% EMQX smoke test, run with: emqx eval "$(cat emqx-smoke.erl)"
%% Subscribes to a topic in the broker, publishes one message, and waits for delivery.
Topic = <<"smoke/test">>,
emqx:subscribe(Topic),
emqx:publish(emqx_message:make(<<"smoke-client">>, Topic, <<"hello">>)),
receive
  {deliver, Topic, Msg} ->
    case emqx_message:payload(Msg) of
      <<"hello">> -> io:format("SMOKE_OK~n");
      Other -> io:format("SMOKE_BAD_PAYLOAD ~p~n", [Other]), halt(1)
    end
after 5000 ->
  io:format("SMOKE_TIMEOUT~n"), halt(1)
end.
