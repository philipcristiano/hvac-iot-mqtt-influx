use std::fmt;

use serde::Deserialize;

use rumqttc::MqttOptions;

#[derive(Clone, Deserialize)]
pub struct Secret(String);

impl fmt::Debug for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[REDACTED]]")
    }
}

impl Into<String> for Secret {
    fn into(self) -> String {
        self.0
    }
}

#[derive(Clone, Debug, Deserialize)]
pub struct MQTTConfig {
    id: Option<String>,
    host: String,
    port: Option<u16>,
    username: String,
    password: Secret,
}

impl Into<MqttOptions> for MQTTConfig {
    fn into(self) -> MqttOptions {
        let mut m = MqttOptions::new(
            self.id.or(Some("hvac_iot".to_string())).unwrap(),
            self.host,
            self.port.or(Some(1883)).unwrap(),
        );
        m.set_credentials(self.username, self.password);
        m
    }
}

#[derive(Clone, Debug, Deserialize)]
pub struct InfluxDBConfig {
    pub host: String,
    pub bucket: String,
    pub token: Secret,
}
