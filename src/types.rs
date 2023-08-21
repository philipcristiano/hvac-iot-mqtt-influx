use bytes::Bytes;
use chrono::{DateTime, Utc};
use influxdb::InfluxDbWriteable;
use serde::Deserialize;
use std::time::SystemTime;
#[derive(Clone, Debug, Deserialize)]
pub struct Event {
    data: EventData,
    meta: EventMeta,
    time: Option<SystemTime>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct EventMeta {
    name: String,
    id_hex: String,
    sid: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(untagged)]
pub enum EventData {
    Simple {
        rssi: i32,
        temp_c: f32,
        rh: f32,
        vbat: f32,
    },
    SimpleCO2 {
        rssi: i32,
        vbat: f32,
        #[serde(alias = "mBar")]
        mbar: f32,
        co2: u32,
        pm10: u16,
        pm100: u16,
        pm25: u16,
    },
    CO2 {
        rssi: i32,
        temp_c: f32,
        rh: f32,
        vbat: f32,
        mbar: f32,
        co2: u32,
        pm10: u16,
        pm100: u16,
        pm25: u16,
    },
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
    rssi: i32,
    temp_c: Option<f32>,
    rh: Option<f32>,
    vbat: f32,
    mbar: Option<f32>,
    co2: Option<u32>,
    pm10: Option<u16>,
    pm100: Option<u16>,
    pm25: Option<u16>,
}

impl From<Event> for WritableEvent {
    fn from(e: Event) -> WritableEvent {
        match e.data {
            EventData::Simple {
                rssi,
                temp_c,
                rh,
                vbat,
            } => WritableEvent {
                time: chrono::offset::Utc::now(),
                name: e.meta.name,
                id_hex: e.meta.id_hex,
                sid: e.meta.sid,
                rssi,
                temp_c: Some(temp_c),
                rh: Some(rh),
                vbat,
                mbar: None,
                co2: None,
                pm10: None,
                pm100: None,
                pm25: None,
            },
            EventData::SimpleCO2 {
                rssi,
                vbat,
                mbar,
                co2,
                pm10,
                pm100,
                pm25,
            } => WritableEvent {
                time: chrono::offset::Utc::now(),
                name: e.meta.name,
                id_hex: e.meta.id_hex,
                sid: e.meta.sid,
                rssi,
                temp_c: None,
                rh: None,
                vbat,
                mbar: Some(mbar),
                co2: Some(co2),
                pm10: Some(pm10),
                pm100: Some(pm100),
                pm25: Some(pm25),
            },
            EventData::CO2 {
                rssi,
                temp_c,
                rh,
                vbat,
                mbar,
                co2,
                pm10,
                pm100,
                pm25,
            } => WritableEvent {
                time: chrono::offset::Utc::now(),
                name: e.meta.name,
                id_hex: e.meta.id_hex,
                sid: e.meta.sid,
                rssi,
                temp_c: Some(temp_c),
                rh: Some(rh),
                vbat,
                mbar: Some(mbar),
                co2: Some(co2),
                pm10: Some(pm10),
                pm100: Some(pm100),
                pm25: Some(pm25),
            },
        }
    }
}
pub fn parse(payload: String) -> Option<Event> {
    let e: Result<Event, _> = serde_json::from_str(&payload);
    if let Ok(e) = e {
        let mut e = e;
        e.time = Some(SystemTime::now());
        return Some(e);
    } else if let Err(er) = e {
        println!("Could not parse payload {:?} due to {:?}", payload, er)
    }
    return None;
}
