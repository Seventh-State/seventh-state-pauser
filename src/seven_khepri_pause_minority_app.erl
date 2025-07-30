%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Seventh State
%%% @doc 
%%%
%%% @end
%%% Created : 29 Jul 2025 by Seventh State <contact@seventhstate.io>
-module(seven_khepri_pause_minority_app).

-behaviour(application).
-export([start/2, stop/1]).


start(_StartType, _StartArgs) ->
    seven_khepri_pause_minority_sup:start_link().

stop(_State) ->
    ok.

