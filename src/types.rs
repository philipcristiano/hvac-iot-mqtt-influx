use chrono::{DateTime, Utc};
use influxdb::InfluxDbWriteable;
use serde::Deserialize;
use std::time::SystemTime;
#[derive(Clone, Debug, Deserialize)]
pub struct Event {
    pub data: EventData,
    pub meta: EventMeta,
    pub time: Option<SystemTime>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct EventMeta {
    pub name: String,
    pub id_hex: String,
    pub sid: String,
}

#[derive(Clone, Debug, Deserialize)]
pub struct EventData {
    rssi: i32,
    vbat: f32,
    #[serde(alias = "mBar")]
    mbar: Option<f32>,
    co2: Option<u32>,
    pm100: Option<u16>,
    pm10: Option<u16>,
    pm25: Option<u16>,
    rh: Option<f32>,
    temp_c: Option<f32>,
    tvoc: Option<u32>,
}

#[derive(Clone, Debug, Deserialize, InfluxDbWriteable)]
pub struct WritableEvent {
    time: DateTime<Utc>,
    #[influxdb(tag)]
    name: String,
    #[influxdb(tag)]
    id_hex: String,
    #[influxdb(tag)]
    sid: String,
    rssi: f32,
    temp_c: Option<f32>,
    rh: Option<f32>,
    vbat: f32,
    mbar: Option<f32>,
    tvoc: Option<f32>,
    co2: Option<f32>,
    pm10: Option<f32>,
    pm100: Option<f32>,
    pm25: Option<f32>,
}

impl From<Event> for WritableEvent {
    fn from(e: Event) -> WritableEvent {
        match e.data {
            EventData {
                tvoc,
                co2,
                mbar,
                pm10,
                pm100,
                pm25,
                rh,
                rssi,
                temp_c,
                vbat,
            } => WritableEvent {
                time: chrono::offset::Utc::now(),
                name: e.meta.name,
                id_hex: e.meta.id_hex,
                sid: e.meta.sid,
                rssi: rssi as f32,
                temp_c,
                rh,
                vbat,
                mbar,
                tvoc: tvoc.map(|i| i as f32),
                co2: co2.map(|i| i as f32),
                pm10: pm10.map(|i| i as f32),
                pm100: pm100.map(|i| i as f32),
                pm25: pm25.map(|i| i as f32),
            },
        }
    }
}
pub fn parse(payload: String) -> Option<Event> {
    let e: Result<Event, _> = serde_json::from_str(&payload);
    tracing::debug!("Payload {:?}", payload);
    if let Ok(e) = e {
        let mut e = e;
        e.time = Some(SystemTime::now());
        return Some(e);
    } else if let Err(er) = e {
        tracing::info!("Could not parse payload {:?} due to {:?}", payload, er)
    }
    return None;
}
