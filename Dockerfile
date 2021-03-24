FROM erlang:23.0.2 AS builder
WORKDIR /app/src
ADD . /app/src
RUN rm -rf /app/src/deps /app/src/_rel

RUN make deps app
RUN make rel
RUN mv /app/src/_rel/hvac_iot_release/hvac_iot_*.tar.gz /app.tar.gz

FROM debian:buster

ENV LOG_LEVEL=info

RUN apt-get update && apt-get install -y openssl && apt-get clean

COPY --from=builder /app.tar.gz /app.tar.gz

WORKDIR /app

RUN tar -xzf /app.tar.gz
ADD config/default.config /hvac_iot/app.config

CMD ["/app/bin/hvac_iot_release", "foreground"]
