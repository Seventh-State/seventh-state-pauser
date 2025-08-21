%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Erlang Solutions Ltd., Seventh State
-module(seven_pauser_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init(_Args) ->
    SupervisorSpecification = #{
        strategy => one_for_one, % one_for_one | one_for_all | rest_for_one | simple_one_for_one
        intensity => 10,
        period => 60},

    ChildSpecifications = [
        #{
            id => seven_pauser,
            start => {seven_pauser, start_link, []},
            restart => permanent, % permanent | transient | temporary
            shutdown => 2000, % use 'infinity' for supervisor child
            type => worker, % worker | supervisor
            modules => [seven_pauser]
        }
    ],

    {ok, {SupervisorSpecification, ChildSpecifications}}.
