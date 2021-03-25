-module(hvac_iot_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	Procs = [
                    #{
                        id => hvac_iot_mqtt_to_influx,
                        start => {hvac_iot_mqtt_to_influx, start_link, []}
                    }],
	{ok, {{one_for_one, 1, 5}, Procs}}.
