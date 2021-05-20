-module(hvac_iot_app).

-behaviour(application).
-include_lib("kernel/include/logger.hrl").

-export([start/2]).
-export([stop/1]).

start(_Type, _Args) ->
    DSN = os:getenv("SENTRY_DSN"),
    case DSN of
        false ->
            ?LOG_INFO(#{what => "Sentry not setup. Set 'SENTRY_DSN'"});
        ActualDSN ->
            ?LOG_INFO(#{what => "Sentry configured"}),
            ok = logger:add_handler(
                eraven,
                er_logger_handler,
                #{
                    level => warning,
                    config => #{
                        dsn => ActualDSN
                    }
                }
            )
    end,

    hvac_iot_sup:start_link().

stop(_State) ->
    ok.
