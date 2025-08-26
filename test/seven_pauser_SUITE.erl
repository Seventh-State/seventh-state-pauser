%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Erlang Solutions Ltd., Seventh State
-module(seven_pauser_SUITE).

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
    inets:start(),
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
    inets:stop(),
    rabbit_ct_helpers:run_steps(Config,
                                rabbit_ct_client_helpers:teardown_steps()
                                ++ rabbit_ct_broker_helpers:teardown_steps()).

init_per_testcase(Testcase, Config) ->
    %% Net tick time was hardecoded to 5 seconds for testing in RabbitMQ recent versions, so we need to set it manually
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
    {Connection, Channel} = open_connection_and_channel(Config, Node1),
    declare_classic_queue(Channel, <<Queue/binary, "_classic">>),
    declare_exclusive_queue(Channel, <<Queue/binary, "_exclusive">>),

    %% test with qq if the connetion is disconnected or blocked when there is a consumer connected
    %% open a new connection to test if the connection is closed when the node is in minority partition
    Connection1 = open_connection(Config, Node1),
    {ok, Channel1} = open_channel(Connection1),
    declare_quorum_queue(Channel1, <<Queue/binary, "_quorum">>),
    consume(Channel1, <<Queue/binary, "_quorum">>),

    ConnectionRef = erlang:monitor(process, Connection),
    ConnectionRef1 = erlang:monitor(process, Connection1),

    %% put Node1 into minority partition
    rabbit_ct_broker_helpers:block_traffic_between(Node1, Node2),
    rabbit_ct_broker_helpers:block_traffic_between(Node1, Node3),
    %% create a long enough disconnection
    wait_for_net_tick_timeout(Config),
    wait_for_net_tick_timeout(Config),
    wait_for_net_tick_timeout(Config),

    assert_connection_closed(ConnectionRef1, Connection1),
    assert_connection_closed(ConnectionRef, Connection),
    assert_http_connection_available(Config, Node1),

    {error, _CannotOpenNewConnection} = open_connection(Config, Node1),
    ?assert(is_pid(open_connection(Config, Node2)), "Connection to Node2 should be able to open"),
    ?assert(is_pid(open_connection(Config, Node3)), "Connection to Node3 should be able to open"),

    %% restore cluster
    rabbit_ct_broker_helpers:allow_traffic_between(Node1, Node2),
    rabbit_ct_broker_helpers:allow_traffic_between(Node1, Node3),
    timer:sleep(10000), % wait for the cluster to stabilize

    {ok, OpenNewChannel} = open_channel(Config, Node1),
    declare_classic_queue(OpenNewChannel, <<Queue/binary, "_classic_recovered">>),
    assert_classic_queue_works(OpenNewChannel, <<Queue/binary, "_classic_recovered">>),

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

declare_quorum_queue(Channel, Queue) ->
    amqp_channel:call(Channel,
                      #'queue.declare'{queue = Queue,
                                       durable = true,
                                       auto_delete = false,
                                       arguments = [{<<"x-queue-type">>, longstr, <<"quorum">>}]}).

declare_auto_delete_queue(Channel, Queue) ->
    amqp_channel:call(Channel,
                      #'queue.declare'{queue = Queue,
                                       durable = false,
                                       auto_delete = true,
                                       arguments = []}).

consume(Channel, Queue) ->
    amqp_channel:subscribe(Channel,
                           #'basic.consume'{queue = Queue,
                                            consumer_tag = <<"test_consumer">>,
                                            no_ack = true},
                           self()),
    receive
        #'basic.consume_ok'{consumer_tag = _ConsumerTag} ->
            ok
    after 5000 ->
        ct:fail("Failed to consume from queue ~p", [Queue])
    end.

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

open_connection(Config, Node) ->
    rabbit_ct_client_helpers:open_unmanaged_connection(Config, Node).

open_channel(Connection) ->
    {ok, Channel} = amqp_connection:open_channel(Connection),
    amqp_channel:call(Channel, #'confirm.select'{}),
    {ok, Channel}.

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

assert_connection_closed(Ref, Pid) ->
    receive
        {'DOWN', Ref, process, Pid, Reason} ->
            ct:pal("Connection closed: ~p~n", [Reason]),
            ?assertMatch({shutdown, {server_initiated_close, _, _}}, Reason);
        {'DOWN', _, process, _, Reason} ->
            ct:pal("Unexpected connection close: ~p~n", [Reason]),
            ?assert(false)
    after 35000 ->
        ?assertNot(is_process_alive(Pid), "Connection should be closed but is still alive")
    end.

assert_http_connection_available(Config, Node) ->
    ?assertMatch({ok, {{_, 200, _}, _, _}}, get(Config, "/api/overview", Node)).

auth_header() ->
    auth_header(<<"guest">>, <<"guest">>).

auth_header(Username, Password) ->
    {"Authorization",
     <<"Basic ", (base64:encode(<<Username/binary, ":", Password/binary>>))/binary>>}.

mgmt_port(Config, Node) ->
    rabbit_ct_broker_helpers:get_node_config(Config, Node, tcp_port_mgmt).

base_uri(Config, Node) ->
    "http://localhost:" ++ integer_to_list(mgmt_port(Config, Node)).

get(Config, API, Node) ->
    httpc:request(get,
                  {base_uri(Config, Node) ++ API, [auth_header()]},
                  [{ssl, [{verify_peer, verify_none}]}],
                  [{body_format, binary}]).
