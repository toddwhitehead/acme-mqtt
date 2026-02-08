# ACME MQTT - Azure Event Grid Integration

A Docker-based MQTT solution that reads messages from an on-premises MQTT broker, augments the data with timestamps, and forwards it to Azure Event Grid. The cloud component receives Event Grid messages and stores them in Azure Blob Storage.

## Architecture

### On-Premises Components

1. **MQTT Broker** (`mqtt-broker/`)
   - Eclipse Mosquitto MQTT broker
   - Listens on port 1883
   - Handles message queuing and delivery

2. **Test Client** (`mqtt-test-client/`)
   - Publishes test messages from JSON data files
   - Simulates IoT devices sending sensor data
   - Configurable publish interval

3. **MQTT Proxy** (`mqtt-proxy/`)
   - Subscribes to MQTT broker
   - Augments messages with:
     - UTC timestamp
     - Processing metadata
     - Source information
   - Forwards to Azure Event Grid MQTT endpoint

### Cloud Components

4. **Azure Function** (`azure-function/`)
   - Event Grid trigger function
   - Receives messages from Event Grid
   - Stores data in Azure Blob Storage

## Prerequisites

- Docker and Docker Compose
- Azure subscription (for cloud deployment)
- Azure Event Grid Topic with MQTT support
- Azure Storage Account
- Azure Function App

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/toddwhitehead/acme-mqtt.git
cd acme-mqtt
```

### 2. Configure Azure Credentials

Copy the example environment file and fill in your Azure credentials:

```bash
cp .env.example .env
```

Edit `.env` and add your Azure Event Grid credentials:

```env
EVENTGRID_ENDPOINT=https://<your-eventgrid-topic>.eventgrid.azure.net/api/events
EVENTGRID_KEY=<your-eventgrid-access-key>
EVENTGRID_TOPIC_HOSTNAME=<your-eventgrid-topic>.eventgrid.azure.net
```

### 3. Start On-Premises Components

```bash
docker-compose up -d
```

This will start:
- MQTT broker on port 1883
- Test client publishing messages every 5 seconds
- Proxy forwarding messages to Azure Event Grid

### 4. View Logs

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f mqtt-broker
docker-compose logs -f mqtt-test-client
docker-compose logs -f mqtt-proxy
```

### 5. Deploy Azure Function

```bash
cd azure-function

# Create Function App (if not already created)
az functionapp create \
  --resource-group <your-resource-group> \
  --consumption-plan-type EP1 \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --name <your-function-app-name> \
  --storage-account <your-storage-account>

# Deploy function
func azure functionapp publish <your-function-app-name>
```

### 6. Configure Event Grid Subscription

Create an Event Grid subscription that triggers your Azure Function:

```bash
az eventgrid event-subscription create \
  --name mqtt-data-subscription \
  --source-resource-id /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.EventGrid/topics/<topic-name> \
  --endpoint-type azurefunction \
  --endpoint /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Web/sites/<function-app-name>/functions/EventGridTrigger
```

## Project Structure

```
acme-mqtt/
├── mqtt-broker/              # MQTT broker (Mosquitto)
│   ├── Dockerfile
│   └── mosquitto.conf
├── mqtt-test-client/         # Test message publisher
│   ├── Dockerfile
│   ├── requirements.txt
│   └── test_client.py
├── mqtt-proxy/               # MQTT to Event Grid proxy
│   ├── Dockerfile
│   ├── requirements.txt
│   └── mqtt_proxy.py
├── azure-function/           # Azure Function for blob storage
│   ├── host.json
│   ├── requirements.txt
│   └── EventGridTrigger/
│       ├── function.json
│       └── __init__.py
├── test-data/                # Sample test data
│   ├── sensor_data.json
│   └── device_status.json
├── docker-compose.yml        # Docker Compose configuration
├── .env.example              # Example environment variables
└── README.md
```

## Configuration

### Environment Variables

#### MQTT Test Client

- `MQTT_BROKER`: MQTT broker hostname (default: `mqtt-broker`)
- `MQTT_PORT`: MQTT broker port (default: `1883`)
- `MQTT_TOPIC`: Topic to publish to (default: `sensor/data`)
- `TEST_DATA_DIR`: Directory containing test data files (default: `/app/test-data`)
- `PUBLISH_INTERVAL`: Seconds between messages (default: `5`)

#### MQTT Proxy

- `MQTT_BROKER`: MQTT broker hostname (default: `mqtt-broker`)
- `MQTT_PORT`: MQTT broker port (default: `1883`)
- `MQTT_TOPIC`: Topic to subscribe to (default: `sensor/data`)
- `EVENTGRID_ENDPOINT`: Azure Event Grid endpoint URL
- `EVENTGRID_KEY`: Azure Event Grid access key
- `EVENTGRID_TOPIC_HOSTNAME`: Azure Event Grid topic hostname

#### Azure Function

- `AzureWebJobsStorage`: Azure Storage connection string
- `BLOB_CONTAINER_NAME`: Blob container name (default: `mqtt-data`)

### Test Data

Add your own test data files in JSON format to the `test-data/` directory. The test client will automatically load and cycle through all JSON files.

Example format:

```json
[
  {
    "sensor_id": "sensor_01",
    "type": "temperature",
    "value": 22.5,
    "unit": "celsius"
  }
]
```

## Message Flow

1. **Test Client** reads JSON files from `test-data/` and publishes to MQTT broker
2. **MQTT Broker** receives and queues messages
3. **MQTT Proxy** subscribes to broker, receives messages
4. **Proxy** augments messages with:
   ```json
   {
     "original_data": { ... },
     "timestamp": "2024-01-01T12:00:00.000Z",
     "processed_by": "mqtt-proxy",
     "source": "on-premises-mqtt"
   }
   ```
5. **Proxy** sends augmented message to Azure Event Grid
6. **Azure Function** is triggered by Event Grid
7. **Function** stores message in Azure Blob Storage with metadata

## Development

### Local Testing (Without Azure)

The system can run in test mode without Azure credentials. The proxy will log messages instead of sending to Event Grid:

```bash
# Start without Azure credentials
docker-compose up -d

# View proxy logs to see augmented messages
docker-compose logs -f mqtt-proxy
```

### Stop Services

```bash
docker-compose down

# Remove volumes
docker-compose down -v
```

### Rebuild Containers

```bash
docker-compose build
docker-compose up -d
```

## Troubleshooting

### MQTT Broker Connection Issues

```bash
# Check if broker is running
docker-compose ps mqtt-broker

# Test connection with mosquitto_sub
docker run -it --rm --network acme-mqtt_mqtt-network eclipse-mosquitto mosquitto_sub -h mqtt-broker -t "sensor/data" -v
```

### Event Grid Issues

- Verify Event Grid endpoint and key are correct
- Check proxy logs for error messages
- Ensure Event Grid topic is configured for CloudEvents schema

### Azure Function Issues

- Check function logs in Azure Portal
- Verify Event Grid subscription is active
- Ensure storage account connection string is configured

## License

See LICENSE file for details.
