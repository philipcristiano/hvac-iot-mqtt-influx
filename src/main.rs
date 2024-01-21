use clap::Parser;
use influxdb::Client;
use influxdb::InfluxDbWriteable;
use rumqttc::{AsyncClient, Event, Packet, QoS};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::fs;
use std::str;

#[derive(Parser, Debug)]
pub struct Args {
    #[arg(short, long, default_value = "hvac_iot.toml")]
    config_file: String,
    #[arg(short, long, value_enum, default_value = "INFO")]
    log_level: tracing::Level,
    #[arg(long, action)]
    log_json: bool,
}

mod auth;
mod types;

#[derive(Clone, Debug, Deserialize)]
struct AppConfig {
    mqtt: auth::MQTTConfig,
    influxdb: auth::InfluxDBConfig,
    sensor: Vec<SensorConfig>,
}

#[derive(Clone, Debug, Deserialize)]
struct SensorConfig {
    id_hex: String,
    overwrite: SensorOverwriteConfig,
}

#[derive(Clone, Debug, Deserialize)]
struct SensorOverwriteConfig {
    name: String,
}

#[tokio::main]
async fn main() {
    // initialize tracing

    let args = Args::parse();
    let subscriber = tracing_subscriber::fmt().with_max_level(args.log_level);
    if args.log_json {
        subscriber.json().init()
    } else {
        subscriber.init()
    };

    let config_file_error_msg = format!("Could not read config file {}", args.config_file);
    let config_file_contents = fs::read_to_string(args.config_file).expect(&config_file_error_msg);

    let app_config: AppConfig =
        toml::from_str(&config_file_contents).expect("Problems parsing config file");

    tracing::debug!("Config {:?}", app_config);
    let name_overwrite_map = app_config
        .sensor
        .into_iter()
        .map(|x| (x.id_hex.clone(), x.overwrite.name))
        .collect::<BTreeMap<_, _>>();

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
                let annotated_event = annotate_event(event, &name_overwrite_map);

                tokio::spawn(async move { post_event(new_client, annotated_event).await });
            }
        }
    }
}

fn annotate_event(event: types::Event, overwrite: &BTreeMap<String, String>) -> types::Event {
    let replacement_name = overwrite
        .get(&event.meta.id_hex)
        .unwrap_or(&event.meta.name);
    let new_meta = types::EventMeta {
        name: replacement_name.clone(),
        ..event.meta
    };
    let new_event = types::Event {
        meta: new_meta,
        ..event
    };
    new_event
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
