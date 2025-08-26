%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Erlang Solutions Ltd., Seventh State
-module(seven_pauser_app).

-behaviour(application).
-export([start/2, stop/1]).


start(_StartType, _StartArgs) ->
    seven_pauser_sup:start_link().

stop(_State) ->
    ok.

