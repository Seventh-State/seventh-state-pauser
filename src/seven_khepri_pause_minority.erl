%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Seventh State
%%% @doc
%%%
%%% @end
%%% Created : 29 Jul 2025 by Seventh State <contact@seventhstate.io>
-module(seven_khepri_pause_minority).

-behaviour(gen_server).

%% API
-export([start/1, stop/1, start_link/0, start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("include/seven_khepri_pause_minority.hrl").

-define(INTERVAL, application:get_env(?MODULE, interval, 3)).
-define(DB, rabbitmq_metadata).

start(Name) ->
    seven_khepri_pause_minority_sup:start_child(Name).

stop(Name) ->
    gen_server:call(Name, stop).

start_link() ->
    start_link(?MODULE).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

init(_Args) ->
    KhepriState = rabbit_khepri:get_feature_state(),
    ClusterPartitionHandling = application:get_env(rabbit, cluster_partition_handling, ignore),
    case {KhepriState, ClusterPartitionHandling} of
        {enabled, pause_minority} ->
            ?INF("Starting ~p with interval ~p seconds", [?MODULE, ?INTERVAL]),
            erlang:send_after(?INTERVAL * 1000, self(), check),
            {ok, #{}};
        _ ->
            ?INF("Skipping ~p initialisation due to Khepri feature state or cluster partition handling settings", [?MODULE]),
            {ok, stopped} % indicates that the server will do nothing
    end.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(check, State) ->
    Nodes = rabbit_nodes:list_members(),
    RunningNodes = rabbit_nodes:list_running(),
    case length(RunningNodes) < length(Nodes) / 2 of
        true when State =:= #{} ->
            ?INF("Minority partition detected, pausing operations", []),
            rabbit_maintenance:suspend_all_client_listeners(),
            %% disconnect everyone from local node?
            %% Connections = rabbit_connection_tracking:list_on_node(node()),
            %% rabbit_connection_tracking_handler:close_connections(Connections, <<"This node is in minority partition">>, 0),
            %% or?
            %% [spawn(fun(Node) -> net_kernel:disconnect(Node) end, Node) || Node <- Nodes -- [node()]],
            erlang:send_after(?INTERVAL * 1000, self(), check),
            {noreply, #{listeners => suspended}};
        false when State =/= #{} ->
            ?INF("Minority partition no longer detected, resuming operations", []),
            rabbit_maintenance:resume_all_client_listeners(),
            erlang:send_after(?INTERVAL * 1000, self(), check),
            {noreply, #{}};
        true ->
            ?DBG("Minority partition detected, but already in suspended state, skipping", []),
            erlang:send_after(?INTERVAL * 1000, self(), check),
            {noreply, State};
        false ->
            ?DBG("No minority partition detected, continuing normal operations", []),
            erlang:send_after(?INTERVAL * 1000, self(), check),
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
