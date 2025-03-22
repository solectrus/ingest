# ingest

Lightweight InfluxDB ingestion proxy with buffering and persistence.

## Features

- Accepts InfluxDB v2 `/api/v2/write` (Line Protocol)
- Reads `Authorization` token, `bucket`, `org`, and `precision` from the request
- Forwards data to InfluxDB (`INFLUX_URL` from environment)
- Buffers failed writes to disk (`buffer.dump`)
- Automatic replay of buffered data every 60 seconds
- Crash-safe with `buffer.replay`

## Example Docker Compose

```yaml
services:
  ingest:
    image: ghcr.io/solectrus/ingest:latest
    environment:
      INFLUX_URL: http://influxdb:8086
    ports:
      - '4567:4567'
```

## Example cURL

```bash
curl -X POST "http://localhost:4567/api/v2/write?bucket=my-bucket&org=my-org&precision=ns" \
  -H "Authorization: Token my-token" \
  -H "Content-Type: text/plain" \
  --data-raw "test_measurement,location=office value=42 $(( $(date +%s) * 1000000000 ))"
```

## Environment Variables

| Variable     | Description                                    |
| ------------ | ---------------------------------------------- |
| `INFLUX_URL` | InfluxDB base URL (e.g., http://influxdb:8086) |

## Buffering Details

- Failed writes are stored in `buffer.dump`
- Replayed automatically every 60 seconds
- Crash-safe: Replay uses `buffer.replay` to avoid data loss

## API Example

### POST `/api/v2/write`

- **Headers:**
  - `Authorization: Token <token>`
  - `Content-Type: text/plain`
- **Query Params:**
  - `bucket`: Target bucket name
  - `org`: Target organization
  - `precision`: Timestamp precision (default: `s`)
- **Body:**
  - Raw InfluxDB Line Protocol

## Healthcheck

`GET /health` → Returns `OK`
