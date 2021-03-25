%%%-------------------------------------------------------------------
%%% @author $AUTHOR
%%% @copyright 2021 $OWNER
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(hvac_iot_mqtt_to_influx).

-include_lib("kernel/include/logger.hrl").

-behaviour(gen_server).

%% API functions
-export([start_link/0]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-record(state, {mqtt_client_pid}).

-define(MQTT_CLIENT_ID, "hvac-iot-mqtt-to-influx").

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

connect_mqtt() ->
    gen_server:cast(?MODULE, connect_mqtt).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    ?LOG_INFO(#{what => "MQTT-to-InfluxDB starting"}),
    io:format("Starting"),

    connect_mqtt(),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(connect_mqtt, State = #state{}) ->
    Host = application:get_env(hvac_iot, mqtt_host, "localhost"),
    User = application:get_env(hvac_iot, mqtt_username, "mqtt"),
    Pass = application:get_env(hvac_iot, mqtt_password, "mqtt"),

    ?LOG_INFO(#{
        what => "MQTT-to-InfluxDB connecting",
        host => Host
    }),
    {ok, MCP} = emqtt:start_link([
        {clientid, ?MQTT_CLIENT_ID},
        {host, Host},
        {username, User},
        {password, Pass}
    ]),
    {ok, _Props} = emqtt:connect(MCP),

    SubOpts = [{qos, 1}],
    {ok, _Props, _ReasonCodes} = emqtt:subscribe(MCP, #{}, [{<<"/metrics">>, SubOpts}]),

    {noreply, State#state{mqtt_client_pid = MCP}};
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({publish, Msg = #{topic := <<"/metrics">>, payload := Payload}}, State) ->
    io:format("publish ~p~n", [Msg]),
    send_to_influxdb(Payload),
    {noreply, State};
handle_info(Info, State) ->
    io:format("Info ~p~n", [Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%%

send_to_influxdb(Line) ->
    Host = application:get_env(hvac_iot, influxdb_host, "localhost"),
    Port = application:get_env(hvac_iot, influxdb_port, 8086),
    Token = application:get_env(hvac_iot, influxdb_token, "default_token"),
    Org = application:get_env(hvac_iot, influxdb_org, "default_org"),
    Bucket = application:get_env(hvac_iot, influxdb_bucket, "default_bucket"),

    SPort = erlang:integer_to_list(Port),

    Query = uri_string:compose_query([{"org", Org}, {"bucket", Bucket}, {"precision", "s"}]),
    Path = "/api/v2/write?" ++ Query,
    URL = "http://" ++ Host ++ ":" ++ SPort ++ Path,
    ?LOG_DEBUG(#{
        what => "Influx Line Request",
        host => Host,
        port => Port,
        org => Org,
        bucket => Bucket,
        line => Line
    }),

    Headers = [{"Authorization", "Token " ++ Token}],

    {ok, Code, RespHeaders, ClientRef} = hackney:request(post, URL, Headers, Line, []),

    ?LOG_DEBUG(#{
        what => "Influx Line Request Response",
        host => Host,
        port => Port,
        org => Org,
        bucket => Bucket,
        line => Line,
        code => Code,
        response_headers => RespHeaders
    }),

    case Code of
        204 ->
            ok;
        _ ->
            {ok, Body} = hackney:body(ClientRef),
            io:format("Resp ~p~n", [{Code, Body}])
    end,

    ok.
