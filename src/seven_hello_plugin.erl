%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Seventh State
%%% @doc 
%%%
%%% @end
%%% Created : 17 Jul 2025 by Seventh State <contact@seventhstate.io>
-module(seven_hello_plugin).

-behaviour(gen_server).

%% API
-export([start/1, stop/1, start_link/0, start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-record(state, {dummy}).
start(Name) ->
    seven_hello_plugin_sup:start_child(Name).

stop(Name) ->
    gen_server:call(Name, stop).

start_link() ->
    start_link(?MODULE).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

init(_Args) ->
    {ok, #state{dummy=1}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
