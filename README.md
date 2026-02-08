# ACME MQTT - Azure Event Grid MQTT Integration

A Docker-based MQTT solution that bridges on-premises MQTT infrastructure with Azure Event Grid's MQTT broker. Messages from local devices flow through a local MQTT broker, get augmented with metadata by a proxy, and are forwarded to Azure Event Grid's MQTT broker for cloud processing.

## Architecture

### On-Premises Components

1. **MQTT Broker** (`mqtt-broker/`)
   - Eclipse Mosquitto MQTT broker
   - Listens on port 1883
   - Handles local message queuing and delivery

2. **Test Client** (`mqtt-test-client/`)
   - Publishes test messages from JSON data files
   - Simulates IoT devices sending sensor data
   - Connects to local MQTT broker
   - Configurable publish interval

3. **MQTT Proxy** (`mqtt-proxy/`)
   - Subscribes to local MQTT broker
   - Augments messages with:
     - UTC timestamp
     - Processing metadata
     - Source information
   - Forwards to Azure Event Grid MQTT broker (port 8883)
   - Supports SAS token or certificate-based authentication

### Cloud Components

4. **Azure Event Grid MQTT Broker**
   - Built-in MQTT 3.1.1 and 5.0 support
   - Handles client authentication and authorization
   - Routes MQTT messages to Event Grid topics
   - Provides scalable, managed MQTT infrastructure

5. **Azure Function** (`azure-function/`)
   - Event Grid trigger function
   - Receives messages from Event Grid topics
   - Stores data in Azure Blob Storage

## Prerequisites

- Docker and Docker Compose
- Azure subscription
- Azure Event Grid namespace with MQTT enabled
- Azure Storage Account
- Azure Function App

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/toddwhitehead/acme-mqtt.git
cd acme-mqtt
```

### 2. Set Up Azure Event Grid MQTT Namespace

Create an Event Grid namespace with MQTT broker enabled:

```bash
# Create Event Grid namespace with MQTT support
az eventgrid namespace create \
  --resource-group <your-resource-group> \
  --name <your-namespace-name> \
  --location <region> \
  --topic-spaces-configuration "{state:Enabled}"

# Register MQTT client for the proxy
az eventgrid namespace client create \
  --resource-group <your-resource-group> \
  --namespace-name <your-namespace-name> \
  --client-name mqtt_proxy \
  --authentication-name mqtt_proxy \
  --state Enabled
```

### 3. Configure Authentication

#### Option A: SAS Token Authentication

Generate a SAS token for your proxy client:

```bash
az eventgrid namespace client generate-sas-token \
  --resource-group <your-resource-group> \
  --namespace-name <your-namespace-name> \
  --client-name mqtt_proxy \
  --expiry-time-utc "2025-12-31T23:59:59Z"
```

#### Option B: Certificate-based Authentication

1. Generate client certificates or use existing ones
2. Upload certificates to Event Grid namespace
3. Place certificates in `./certs` directory

### 4. Configure Environment Variables

Copy the example environment file and fill in your Azure credentials:

```bash
cp .env.example .env
```

Edit `.env` and add your Azure Event Grid MQTT credentials:

```env
# For SAS token authentication
EVENTGRID_MQTT_HOSTNAME=<your-namespace>.westus2.ts.eventgrid.azure.net
MQTT_CLIENT_ID=mqtt_proxy
MQTT_USERNAME=mqtt_proxy
MQTT_PASSWORD=<your-sas-token>
```

### 5. Configure Event Grid Routing

Create routing rules to forward MQTT messages to Event Grid topics:

```bash
# Create a topic space
az eventgrid namespace topic-space create \
  --resource-group <your-resource-group> \
  --namespace-name <your-namespace-name> \
  --name sensor-data \
  --topic-templates "sensor/#"

# Create an Event Grid topic for the Azure Function
az eventgrid topic create \
  --resource-group <your-resource-group> \
  --name mqtt-events \
  --location <region>

# Create routing configuration (Event Grid namespace -> Topic)
# This is configured through the Azure Portal or ARM templates
```

### 6. Start On-Premises Components

```bash
docker-compose up -d
```

This will start:
- Local MQTT broker on port 1883
- Test client publishing messages every 5 seconds to local broker
- Proxy forwarding messages from local broker to Azure Event Grid MQTT broker

### 7. View Logs

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f mqtt-broker
docker-compose logs -f mqtt-test-client
docker-compose logs -f mqtt-proxy
```

### 8. Deploy Azure Function

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

### 9. Configure Event Grid Subscription

Create an Event Grid subscription that triggers your Azure Function:

```bash
az eventgrid event-subscription create \
  --name mqtt-data-subscription \
  --source-resource-id /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.EventGrid/topics/mqtt-events \
  --endpoint-type azurefunction \
  --endpoint /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Web/sites/<function-app-name>/functions/EventGridTrigger
```

## Project Structure

```
acme-mqtt/
├── mqtt-broker/              # Local MQTT broker (Mosquitto)
│   ├── Dockerfile
│   └── mosquitto.conf
├── mqtt-test-client/         # Test message publisher
│   ├── Dockerfile
│   ├── requirements.txt
│   └── test_client.py
├── mqtt-proxy/               # Local MQTT to Event Grid MQTT bridge
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
├── certs/                    # Client certificates (for cert auth)
│   └── .gitkeep
├── docker-compose.yml        # Docker Compose configuration
├── .env.example              # Example environment variables
└── README.md
```

## Configuration

### Environment Variables

#### MQTT Test Client

- `MQTT_BROKER`: Local MQTT broker hostname (default: `mqtt-broker`)
- `MQTT_PORT`: Local MQTT broker port (default: `1883`)
- `MQTT_TOPIC`: Topic to publish to (default: `sensor/data`)
- `TEST_DATA_DIR`: Directory containing test data files (default: `/app/test-data`)
- `PUBLISH_INTERVAL`: Seconds between messages (default: `5`)

#### MQTT Proxy

Local MQTT broker settings:
- `LOCAL_MQTT_BROKER`: Local MQTT broker hostname (default: `mqtt-broker`)
- `LOCAL_MQTT_PORT`: Local MQTT broker port (default: `1883`)
- `LOCAL_MQTT_TOPIC`: Topic to subscribe to (default: `sensor/data`)

Azure Event Grid MQTT settings (required):
- `EVENTGRID_MQTT_HOSTNAME`: Azure Event Grid MQTT namespace hostname
- `EVENTGRID_MQTT_PORT`: MQTT port (default: `8883`)
- `EVENTGRID_MQTT_TOPIC`: Topic to publish to on Event Grid (default: `sensor/data`)
- `MQTT_CLIENT_ID`: Client identifier (must be registered in Event Grid)

Authentication (choose one):
- SAS Token:
  - `MQTT_USERNAME`: Client username
  - `MQTT_PASSWORD`: SAS token
- Certificate:
  - `MQTT_CERT_FILE`: Client certificate path
  - `MQTT_KEY_FILE`: Client key path
  - `MQTT_CA_CERTS`: CA certificate path (optional)

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

1. **Test Client** reads JSON files from `test-data/` and publishes to local MQTT broker
2. **Local MQTT Broker** receives and queues messages
3. **MQTT Proxy** subscribes to local broker, receives messages
4. **Proxy** augments messages with metadata:
   ```json
   {
     "original_data": { ... },
     "timestamp": "2024-01-01T12:00:00.000Z",
     "processed_by": "mqtt-proxy",
     "source": "on-premises-mqtt"
   }
   ```
5. **Proxy** publishes augmented message to Azure Event Grid MQTT broker (port 8883 with TLS)
6. **Event Grid MQTT Broker** authenticates and routes messages to Event Grid topics
7. **Azure Function** is triggered by Event Grid topic
8. **Function** stores message in Azure Blob Storage with metadata

## Development

### Local Testing

The MQTT proxy requires Azure Event Grid MQTT namespace credentials. Without credentials, the proxy runs in test mode and logs messages instead of forwarding:

```bash
# Start without Azure credentials (test mode)
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

### Local MQTT Broker Connection Issues

```bash
# Check if broker is running
docker-compose ps mqtt-broker

# Test connection with mosquitto_sub
docker run -it --rm --network acme-mqtt_mqtt-network eclipse-mosquitto mosquitto_sub -h mqtt-broker -t "sensor/data" -v
```

### Event Grid MQTT Issues

- Verify Event Grid MQTT hostname and credentials are correct
- Check proxy logs for error messages
- Ensure MQTT client is registered in Event Grid namespace
- Verify TLS/SSL certificates are valid (if using certificate auth)
- Check that SAS token hasn't expired (if using SAS auth)

### Azure Function Issues

- Check function logs in Azure Portal
- Verify Event Grid subscription is active
- Ensure storage account connection string is configured

## License

See LICENSE file for details.
