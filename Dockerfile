
FROM erlang:24 AS BUILDER
RUN mkdir -p /app/hvac_iot
ADD Makefile rebar3 rebar.* /app/hvac_iot
WORKDIR /app/hvac_iot
RUN make compile

ADD . /app/hvac_iot
RUN make compile
RUN make tar && mv /app/hvac_iot/_build/default/rel/hvac_iot_release/hvac_iot_release-*.tar.gz /app.tar.gz


FROM debian:bullseye

ENV LOG_LEVEL=info
RUN apt-get update && apt-get install -y openssl && apt-get clean
COPY --from=BUILDER /app.tar.gz /app.tar.gz

WORKDIR /app
EXPOSE 8000

RUN tar -xzf /app.tar.gz

CMD ["/app/bin/hvac_iot_release", "foreground"]
