# hvac-iot-mqtt-influx
MQTT -> InfluxDB processor for HVAC-IoT project


## Config

Config file location is `${CONFIG_ROOT}/app.config`

```
[{hvac_iot, [
    {mqtt_host, "localhost"},
    {mqtt_username, "hvac_iot"},
    {mqtt_password, "hvac_iot"},
    {influxdb_token, "Token"},
    {influxdb_host, "localhost"},
    {influxdb_port, 8086},
    {influxdb_org, "hvac-iot"},
    {influxdb_bucket, "sensors"}
]}].
```
