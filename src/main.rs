use clap::Parser;
use influxdb::InfluxDbWriteable;
use influxdb::{Client, Query, ReadQuery, Timestamp};
use rumqttc::{AsyncClient, Event, Packet, Publish, QoS};
use serde::Deserialize;
use std::fs;
use std::str;

#[derive(Parser, Debug)]
pub struct Args {
    #[arg(short, long, default_value = "hvac_iot.toml")]
    config_file: String,
}

mod auth;
mod types;

#[derive(Clone, Debug, Deserialize)]
struct AppConfig {
    mqtt: auth::MQTTConfig,
    influxdb: auth::InfluxDBConfig,
}

#[tokio::main]
async fn main() {
    // initialize tracing
    tracing_subscriber::fmt::init();

    let args = Args::parse();
    let config_file_error_msg = format!("Could not read config file {}", args.config_file);
    let config_file_contents = fs::read_to_string(args.config_file).expect(&config_file_error_msg);

    let app_config: AppConfig =
        toml::from_str(&config_file_contents).expect("Problems parsing config file");
    tracing::debug!("Config {:?}", app_config);
    let influx_client = Client::new(app_config.influxdb.host, app_config.influxdb.bucket)
        .with_token(app_config.influxdb.token);

    let (mqtt_client, mut eventloop) = AsyncClient::new(app_config.mqtt.into(), 10);
    mqtt_client
        .subscribe("/metrics_json", QoS::AtMostOnce)
        .await
        .unwrap();

    loop {
        let notification = eventloop.poll().await.unwrap();
        let event_payload = match notification {
            Event::Incoming(Packet::Publish(p)) => String::from_utf8(p.payload.into()).ok(),
            _ => None,
        };
        if let Some(ep) = event_payload {
            let metric = types::parse(ep);
            tracing::debug!("Event = {:?}", &metric);
            let new_client = influx_client.clone();
            if let Some(event) = metric {
                tokio::spawn(async move { post_event(new_client, event).await });
            }
        }
    }
}

async fn post_event(client: Client, e: types::Event) -> () {
    let writable: types::WritableEvent = e.into();
    let query = writable.into_query("sensor_reading");
    tracing::debug!("Writable metric on {:?}", query);
    match client.query(query).await {
        Ok(r) => tracing::debug!("Result Posting to InfluxDB: {:?}", r),
        Err(e) => tracing::error!("Error Posting to InfluxDB: {:?}", e),
    }
}

// impl<E> From<E> for AuthError
// where
//     E: Into<anyhow::Error>,
// {
//     fn from(err: E) -> Self {
//         Self(err.into())
//     }
// }
