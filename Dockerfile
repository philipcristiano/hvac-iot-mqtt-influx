FROM erlang:25.0.2 AS builder
WORKDIR /app/src
ADD . /app/src
RUN rm -rf /app/src/deps /app/src/_rel

FROM elixir:1.14.2 AS ELIXIR_BUILDER
ENV MIX_REBAR=/app/hvac_iot/rebar3
RUN mkdir -p /app/hvac_iot
ADD Makefile rebar3 rebar.* /app/hvac_iot
WORKDIR /app/hvac_iot
RUN mix local.rebar --force rebar3 $MIX_REBAR
RUN mix local.hex --force
RUN $MIX_REBAR version
RUN make compile

ADD . /app/hvac_iot
RUN $MIX_REBAR
RUN make compile
RUN make tar && mv /app/hvac_iot/_build/default/rel/hvac_iot_release/hvac_iot_release-*.tar.gz /app.tar.gz


FROM debian:bullseye

ENV LOG_LEVEL=info
RUN apt-get update && apt-get install -y openssl && apt-get clean
COPY --from=ELIXIR_BUILDER /app.tar.gz /app.tar.gz

WORKDIR /app
EXPOSE 8000

RUN tar -xzf /app.tar.gz

CMD ["/app/bin/hvac_iot_release", "foreground"]
