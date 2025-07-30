%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Seventh State
%%% @doc 
%%%
%%% @end
%%% Created : 30 Jul 2025 by Seventh State <contact@seventhstate.io>
-module(seven_khepri_pause_minority_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

all() ->
    [{group, clustered_3}].

groups() ->
    [{clustered_3, [], [partition_test]}].

%% -------------------------------------------------------------------
%% Test suite setup/teardown
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    rabbit_ct_helpers:run_setup_steps(Config, []).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config).

init_per_group(clustered_3 = Group, Config) ->
    init_per_group(Group, Config, 3);
init_per_group(Group, Config) ->
    init_per_group(Group, Config, 1).

init_per_group(Group, Config, NodesCount) ->
    Config0 =
        rabbit_ct_helpers:set_config(Config,
                                     [{rmq_nodes_count, NodesCount},
                                      {rmq_nodename_suffix, Group},
                                      {net_ticktime, 3},
                                      {metadata_store, khepri}]),
    Config1 =
        rabbit_ct_helpers:merge_app_env(Config0,
                                        [{rabbit, [{cluster_partition_handling, pause_minority}]}]),
    rabbit_ct_helpers:run_steps(Config1,
                                [fun rabbit_ct_broker_helpers:configure_dist_proxy/1]
                                ++ rabbit_ct_broker_helpers:setup_steps()
                                ++ rabbit_ct_client_helpers:setup_steps()).

end_per_group(_, Config) ->
    rabbit_ct_helpers:run_steps(Config,
                                rabbit_ct_client_helpers:teardown_steps()
                                ++ rabbit_ct_broker_helpers:teardown_steps()).

init_per_testcase(Testcase, Config) ->
    %% %% Net tick time was hardecoded to 5 seconds for testing in RabbitMQ recent versions, so we need to set it manually
    rabbit_ct_broker_helpers:rpc_all(Config, application, set_env, [kernel, net_ticktime, 3]),
    reset_node_states(Config),
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).

%% -------------------------------------------------------------------
%% Test cases
%% -------------------------------------------------------------------

partition_test(Config) ->
    Node1 = nodename(Config, 0),
    Node2 = nodename(Config, 1),
    Node3 = nodename(Config, 2),
    
    Queue = atom_to_binary(?FUNCTION_NAME),
    {ok, Channel1} = open_channel(Config, Node1),
    declare_classic_queue(Channel1, <<Queue/binary, "_classic">>),
    declare_exclusive_queue(Channel1, <<Queue/binary, "_exclusive">>),
    
    % put Node1 into minority partition
    rabbit_ct_broker_helpers:block_traffic_between(Node1, Node2),
    rabbit_ct_broker_helpers:block_traffic_between(Node1, Node3),
    timer:sleep(5000), % wait for the minority partition to be detected

    %% RunningNodes = rabbit_ct_broker_helpers:rpc_all(Config, rabbit_nodes, list_running, []),
    %% Nodes = rabbit_ct_broker_helpers:rpc_all(Config, rabbit_nodes, list_members, []),

    %% can publish and consume from predeclared queues and connections from minority node
    assert_classic_queue_works(Channel1, <<Queue/binary, "_classic">>),
    assert_exclusive_queue_works(Channel1, <<Queue/binary, "_exclusive">>),

    {ok, CanOpenChannelFromOldConnection} = open_channel(Config, Node1),
    ?assertMatch({'EXIT', _}, catch declare_classic_queue(CanOpenChannelFromOldConnection, <<"cannot declare classic queue">>)),

    %% cannot open new connection and channel from minority node
    ?assertMatch({'EXIT',{_,"Timed out waiting for connection to open"}}, catch open_connection_and_channel(Config, Node1)),

    rabbit_ct_broker_helpers:allow_traffic_between(Node1, Node2),
    rabbit_ct_broker_helpers:allow_traffic_between(Node1, Node3),

    wait_for_net_tick_timeout(Config),

    ok.

declare_classic_queue(Channel, Queue) ->
    amqp_channel:call(Channel,
                      #'queue.declare'{queue = Queue,
                                       durable = true,
                                       auto_delete = false,
                                       arguments = []}).

declare_exclusive_queue(Channel, Queue) ->
    amqp_channel:call(Channel,
                      #'queue.declare'{queue = Queue,
                                       durable = false,
                                       auto_delete = true,
                                       exclusive = true,
                                       arguments = []}).

assert_classic_queue_works(Channel, Queue) ->
    Payload = crypto:strong_rand_bytes(64),
    amqp_channel:call(Channel, #'queue.purge'{queue = Queue}),
    amqp_channel:call(Channel,
                      #'basic.publish'{exchange = <<>>,
                                       routing_key = Queue,
                                       mandatory = false,
                                       immediate = false},
                      #amqp_msg{payload = Payload}),
    true = amqp_channel:wait_for_confirms(Channel, {5, second}),
    {#'basic.get_ok'{}, #amqp_msg{payload = Payload}} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue, no_ack = true}).

assert_exclusive_queue_works(Channel, Queue) ->
    Payload = crypto:strong_rand_bytes(64),
    amqp_channel:call(Channel, #'queue.purge'{queue = Queue}),
    amqp_channel:call(Channel,
                      #'basic.publish'{exchange = <<>>,
                                       routing_key = Queue,
                                       mandatory = false,
                                       immediate = false},
                      #amqp_msg{payload = Payload}),
    true = amqp_channel:wait_for_confirms(Channel, {5, second}),
    {#'basic.get_ok'{}, #amqp_msg{payload = Payload}} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue, no_ack = true}).

nodename(Config, N) ->
    Nodenames = nodenames(Config),
    Nodename = lists:nth(N + 1, Nodenames),
    Nodename.

nodenames(Config) ->
    Nodenames = rabbit_ct_broker_helpers:get_node_configs(Config, nodename),
    Nodenames.

open_channel(Config, Node) ->
    Channel = rabbit_ct_client_helpers:open_channel(Config, Node),
    amqp_channel:call(Channel, #'confirm.select'{}),
    {ok, Channel}.

open_connection_and_channel(Config, Node) ->
    {Connection, Channel} = rabbit_ct_client_helpers:open_connection_and_channel(Config, Node),
    amqp_channel:call(Channel, #'confirm.select'{}),
    {Connection, Channel}.

wait_for_net_tick_timeout(_Config) ->
    timer:sleep(15000).

reset_node_states(Config) ->
    Nodes = nodenames(Config),
    lists:foreach(fun(N) ->
                     lists:foreach(fun(N2) ->
                                      ok = rabbit_ct_broker_helpers:allow_traffic_between(N, N2)
                                   end,
                                   Nodes)
                  end,
                  Nodes).
