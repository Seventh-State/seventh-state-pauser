%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Seventh State
%%% @doc
%%%
%%% @end
%%% Created : 29 Jul 2025 by Seventh State <contact@seventhstate.io>
-module(seven_pauser).

-behaviour(gen_server).

%% API
-export([start/1, stop/1, start_link/0, start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-include("include/seven_pauser.hrl").

-include_lib("rabbit_common/include/rabbit.hrl").

-define(INTERVAL, application:get_env(?MODULE, interval, 5)).
-define(DB, rabbitmq_metadata).

start(Name) ->
    seven_pauser_sup:start_child(Name).

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
            ?INF("Seventh State PauseR is initialised and running with interval "
                 "~p seconds",
                 [?INTERVAL]),
            erlang:send_after(?INTERVAL * 1000, self(), check),
            {ok, #{listeners => running}};
        _ ->
            ?INF("Seventh State PauseR is not initialised: enable khepri-db feature "
                 "flag and set cluster_partition_handling=pause_minority, then "
                 "restart RabbitMQ to initialise the plugin",
                 []),
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
    IsMinority = length(RunningNodes) < length(Nodes) / 2,
    case IsMinority of
        true when State =:= #{listeners => running} ->
            db_state(),
            ?INF("Minority partition detected, pausing operations", []),
            suspend_listeners(),
            close_connections(),
            erlang:send_after(?INTERVAL * 1000, self(), check),
            {noreply, #{listeners => suspended}};
        false when State =:= #{listeners => suspended} ->
            ?INF("Minority partition no longer detected, resuming operations", []),
            resume_listeners(),
            erlang:send_after(?INTERVAL * 1000, self(), check),
            {noreply, #{listeners => running}};
        true ->
            ?DBG("Minority partition detected, but already in suspended state, "
                 "skipping",
                 []),
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

suspend_listeners() ->
    Listeners = listeners(),
    ?INF("Asked to suspend ~b client connection listeners. No new client "
         "connections will be accepted until these listeners are resumed!",
         [length(Listeners)]),
    lists:foreach(fun ranch:suspend_listener/1, Listeners).

resume_listeners() ->
    Listeners = listeners(),
    ?INF("Asked to resume ~b client connection listeners. New client "
         "connections will be accepted again!",
         [length(Listeners)]),
    lists:foreach(fun ranch:resume_listener/1, Listeners).

listeners() ->
    [rabbit_networking:ranch_ref(Addr, Port)
     || #listener{node = Node,
                  protocol = Protocol,
                  ip_address = Addr,
                  port = Port}
            <- rabbit_networking:node_client_listeners(node()),
        Node =:= node(),
        Protocol =/= clustering,
        Protocol =/= http].

close_connections() ->
    Connections = rabbit_connection_tracking:list_on_node(node()),
    [spawn(fun() ->
              rabbit_networking:close_connection(Pid,
                                                 <<"Node ",
                                                   (atom_to_binary(node()))/binary,
                                                   " is in minority partition">>)
           end)
     || #tracked_connection{pid = Pid, type = network} <- Connections].

db_state() ->
    case catch ets:lookup(ra_state, ?DB) of
        [] ->
            ?WRN("Failed to get state of ~p on node ~p", [?DB, node()]);
        [{?DB, State, _}] when State =/= leader andalso State =/= follower ->
            ?WRN("State of ~p on node ~p is ~p, expected leader or follower", [?DB, node(), State]);
        Error ->
            ?ERR("Unexpected error while checking state of ~p on node ~p: ~p", [?DB, node(), Error])
    end.
