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
-export([
    start_link/0,
    connect_mqtt/0
]).

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
    process_flag(trap_exit, true),

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
        what => "MQTT-to-InfluxDB service sleep starting",
        host => Host
    }),
    ?LOG_INFO(#{
        what => "MQTT-to-InfluxDB service wake starting",
        host => Host
    }),
    {ok, MCP} = emqtt:start_link([
        {clientid, ?MQTT_CLIENT_ID},
        {host, Host},
        {username, User},
        {password, Pass}
    ]),
    ?LOG_INFO(#{
        what => "MQTT-to-InfluxDB connecting",
        host => Host
    }),

    case emqtt:connect(MCP) of
        {ok, _Props} ->
            ?LOG_INFO(#{
                what => "MQTT-to-InfluxDB connection attempt",
                host => Host
            }),

            SubOpts = [{qos, 1}],
            {ok, _Props, _ReasonCodes} = emqtt:subscribe(MCP, #{}, [{<<"/metrics">>, SubOpts}]),
            {ok, _Props, _ReasonCodes} = emqtt:subscribe(MCP, #{}, [{<<"/metrics_json">>, SubOpts}]),

            {noreply, State#state{mqtt_client_pid = MCP}};
        {error, Reason} ->
            ?LOG_INFO(#{
                what => "MQTT-to-InfluxDB connection attempt failed",
                host => Host,
                reason => Reason
            }),
            {noreply, State#state{mqtt_client_pid = MCP}}
    end;
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
    ?LOG_DEBUG(#{
        what => metrics_message,
        payload => Payload,
        msg => Msg
    }),
    send_to_influxdb(Payload),
    {noreply, State};
handle_info({publish, Msg = #{topic := <<"/metrics_json">>, payload := Payload}}, State) ->
    Data = jsx:decode(Payload, [return_maps]),
    InfluxMsg = metric_data_to_influx_line(Data),
    send_to_influxdb(InfluxMsg),
    ?LOG_DEBUG(#{
        what => metrics_json_message,
        payload => Payload,
        influx_msg => InfluxMsg,
        msg => Msg
    }),
    {noreply, State};
handle_info({'EXIT', Pid, Reason}, State = #state{mqtt_client_pid = Pid}) ->
    ?LOG_INFO(#{
        what => "MQTT Connect process exited, will try again",
        pid => Pid,
        reason => Reason
    }),

    {ok, _TRef} = timer:apply_after(5000, ?MODULE, connect_mqtt, []),
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

    Headers = [{<<"Authorization">>, erlang:list_to_binary("Token " ++ Token)}],

    Resp = hackney:request(post, URL, Headers, Line, []),
    handle_influxdb_response(URL, Resp).

handle_influxdb_response(URL, {ok, Code, RespHeaders, ClientRef}) ->
    {ok, Body} = hackney:body(ClientRef),
    ?LOG_DEBUG(#{
        what => "Influx Line Request Response",
        url => URL,
        code => Code,
        body => Body,
        response_headers => RespHeaders
    }),

    case Code of
        204 ->
            ok;
        _ ->
            ?LOG_ERROR(#{
                what => influx_http_error,
                url => URL,
                response => Body
            })
    end,

    ok;
handle_influxdb_response(URL, {error, econnrefused}) ->
    ?LOG_INFO(#{
        what => "Influx HTTP Connection refused",
        url => URL
    }),
    ok.

metric_data_to_influx_line(#{
    <<"type">> := Type,
    <<"meta">> := Meta,
    <<"data">> := Data
}) when is_binary(Type) ->
    InfluxMeta = map_to_influx(Meta),
    <<_Comma:1/binary, InfluxData/binary>> = map_to_influx(Data),

    <<Type/binary, InfluxMeta/binary, <<" ">>/binary, InfluxData/binary>>;
metric_data_to_influx_line(#{
    <<"id">> := ID,
    <<"sid">> := SID,
    <<"id_hex">> := IDHex,
    <<"temp_c">> := TempC,
    <<"rh">> := RH,
    <<"rssi">> := RSSI,
    <<"vbat">> := VBat
}) ->
    IDBin = list_to_binary(integer_to_list(ID)),
    RSSIBin = list_to_binary(integer_to_list(RSSI)),

    TempCBin = float_to_binary(TempC),
    RHBin = float_to_binary(RH),
    VBatBin = float_to_binary(VBat),

    <<<<"sensor_reading">>/binary, <<",id=">>/binary, IDBin/binary, <<",sid=">>/binary, SID/binary,
        <<",id_hex=">>/binary, IDHex/binary,

        <<" rssi=">>/binary, RSSIBin/binary, <<",tc=">>/binary, TempCBin/binary, <<",rh=">>/binary,
        RHBin/binary, <<",vbat=">>/binary, VBatBin/binary>>.

map_to_influx(M) when is_map(M) ->
    maps:fold(
        fun(K, V, AccIn) ->
            VB = to_bin(V),
            <<AccIn/binary, <<",">>/binary, K/binary, <<"=">>/binary, VB/binary>>
        end,
        <<"">>,
        M
    ).

to_bin(B) when is_binary(B) ->
    B;
to_bin(I) when is_integer(I) ->
    list_to_binary(integer_to_list(I));
to_bin(F) when is_float(F) ->
    float_to_binary(F, [{decimals, 4}, compact]).
