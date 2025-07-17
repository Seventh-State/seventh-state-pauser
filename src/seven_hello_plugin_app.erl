%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Seventh State
%%% @doc 
%%%
%%% @end
%%% Created : 17 Jul 2025 by Seventh State <contact@seventhstate.io>
-module(seven_hello_plugin_app).

-behaviour(application).
-export([start/2, stop/1]).


start(_StartType, _StartArgs) ->
    case seven_hello_plugin_sup:start_link() of
        {ok, Pid} ->
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    ok.

