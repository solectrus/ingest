# SOLECTRUS Ingest

[![Build & Push Docker Image](https://github.com/solectrus/ingest/actions/workflows/ci.yml/badge.svg)](https://github.com/solectrus/ingest/actions/workflows/ci.yml)

Lightweight InfluxDB ingestion proxy with **buffering**, **house power calculation**, and **reliable persistence**.

## Features

- Accepts InfluxDB v2 `/api/v2/write` (Line Protocol)
- Reliable **retries** and **batch forwarding** to InfluxDB (`INFLUX_URL`)
- Automatic **house power calculation** based on incoming sensor values (overrides incoming house_power)
- Buffers all writes to SQLite

## Example Docker Compose

```yaml
services:
  ingest:
    image: ghcr.io/solectrus/ingest:latest
    env_file: .env
    ports:
      - '4567:4567'
```

## Environment Variables

| Variable                                  | Description                                           |
| ----------------------------------------- | ----------------------------------------------------- |
| `INFLUX_URL`                              | InfluxDB base URL (e.g., http://influxdb:8086)        |
| `INFLUX_SENSOR_INVERTER_POWER`            | Sensor for inverter power (Format: measurement:field) |
| `INFLUX_SENSOR_GRID_IMPORT_POWER`         | Sensor for grid import power                          |
| `INFLUX_SENSOR_GRID_EXPORT_POWER`         | Sensor for grid export power                          |
| `INFLUX_SENSOR_BATTERY_DISCHARGING_POWER` | Sensor for battery discharging power                  |
| `INFLUX_SENSOR_BATTERY_CHARGING_POWER`    | Sensor for battery charging power                     |
| `INFLUX_SENSOR_BALCONY_INVERTER_POWER`    | Sensor for balcony inverter power                     |
| `INFLUX_SENSOR_WALLBOX_POWER`             | Sensor for wallbox power                              |
| `INFLUX_SENSOR_HEATPUMP_POWER`            | Sensor for heat pump power                            |
| `INFLUX_SENSOR_HOUSE_POWER`               | Sensor for house power                                |
| `INFLUX_EXCLUDE_FROM_HOUSE_POWER`         | Exclude sensors from house power calculation          |

## API Endpoints

### POST `/api/v2/write`

- **Headers:**
  - `Authorization: Token <token>`
  - `Content-Type: text/plain`
- **Query Params:**
  - `bucket`: Target bucket
  - `org`: Target organization
  - `precision`: Timestamp precision (default: `ns`)
- **Body:** InfluxDB Line Protocol
- **Behavior:**
  - Buffers incoming data
  - Triggers house power recalculation if relevant
  - Adds outgoing data to the write queue

## Healthcheck

```http
GET /health
```

Returns `OK` if the service is running.

## Example cURL

```bash
curl -X POST "http://localhost:4567/api/v2/write?bucket=my-bucket&org=my-org&precision=ns" \
  -H "Authorization: Token my-token" \
  -H "Content-Type: text/plain" \
  --data-raw "test_measurement,location=office value=42 $(( $(date +%s) * 1000000000 ))"
```

## How it works

- Incoming data is **persisted** in SQLite
- An internal `OutboxWorker` forwards queued writes to InfluxDB in **batches**
- `HousePowerCalculator` triggers on relevant sensor updates
- `CleanupWorker` removes old incoming data after 12 hours

## Robust by Design

- Survives InfluxDB downtime
- Retains all incoming data until confirmed write
- Can be replayed or recalculated later
