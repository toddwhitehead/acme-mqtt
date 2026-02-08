#!/usr/bin/env python3
"""
MQTT to Azure Event Grid MQTT Broker Proxy
Subscribes to local MQTT broker, augments messages with timestamp, and publishes to Azure Event Grid MQTT broker.
"""

import json
import os
import logging
import ssl
from datetime import datetime, timezone
import paho.mqtt.client as mqtt

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment variables - Local MQTT Broker
LOCAL_MQTT_BROKER = os.getenv('LOCAL_MQTT_BROKER', 'mqtt-broker')
LOCAL_MQTT_PORT = int(os.getenv('LOCAL_MQTT_PORT', 1883))
LOCAL_MQTT_TOPIC = os.getenv('LOCAL_MQTT_TOPIC', 'sensor/data')

# Azure Event Grid MQTT Broker settings
EVENTGRID_MQTT_HOSTNAME = os.getenv('EVENTGRID_MQTT_HOSTNAME', '')
EVENTGRID_MQTT_PORT = int(os.getenv('EVENTGRID_MQTT_PORT', 8883))
EVENTGRID_MQTT_TOPIC = os.getenv('EVENTGRID_MQTT_TOPIC', 'sensor/data')

# Authentication settings for Event Grid
MQTT_CLIENT_ID = os.getenv('MQTT_CLIENT_ID', 'mqtt-proxy')
MQTT_USERNAME = os.getenv('MQTT_USERNAME', '')  # For SAS token auth
MQTT_PASSWORD = os.getenv('MQTT_PASSWORD', '')  # SAS token
MQTT_CERT_FILE = os.getenv('MQTT_CERT_FILE', '')  # Client certificate path
MQTT_KEY_FILE = os.getenv('MQTT_KEY_FILE', '')  # Client key path
MQTT_CA_CERTS = os.getenv('MQTT_CA_CERTS', '')  # CA certificate path

# MQTT clients
local_client = None
eventgrid_client = None


def init_eventgrid_mqtt_client():
    """Initialize Azure Event Grid MQTT client."""
    global eventgrid_client
    
    if not EVENTGRID_MQTT_HOSTNAME:
        logger.warning("Azure Event Grid MQTT hostname not configured. Running in test mode.")
        return None
    
    try:
        # Create MQTT client for Event Grid
        eventgrid_client = mqtt.Client(client_id=MQTT_CLIENT_ID, protocol=mqtt.MQTTv311)
        
        # Configure TLS/SSL
        if MQTT_CERT_FILE and MQTT_KEY_FILE:
            # Certificate-based authentication
            logger.info("Configuring certificate-based authentication for Event Grid")
            ca_certs = MQTT_CA_CERTS if MQTT_CA_CERTS else None
            eventgrid_client.tls_set(
                ca_certs=ca_certs,
                certfile=MQTT_CERT_FILE,
                keyfile=MQTT_KEY_FILE,
                cert_reqs=ssl.CERT_REQUIRED,
                tls_version=ssl.PROTOCOL_TLS_CLIENT
            )
        else:
            # SAS token authentication
            logger.info("Configuring SAS token authentication for Event Grid")
            if MQTT_USERNAME and MQTT_PASSWORD:
                eventgrid_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
            # Set up TLS without client certificates
            eventgrid_client.tls_set(cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)
        
        # Set callbacks
        eventgrid_client.on_connect = on_eventgrid_connect
        eventgrid_client.on_disconnect = on_eventgrid_disconnect
        
        # Connect to Event Grid MQTT broker
        logger.info(f"Connecting to Event Grid MQTT broker at {EVENTGRID_MQTT_HOSTNAME}:{EVENTGRID_MQTT_PORT}")
        eventgrid_client.connect(EVENTGRID_MQTT_HOSTNAME, EVENTGRID_MQTT_PORT, 60)
        eventgrid_client.loop_start()
        
        logger.info(f"Initialized Event Grid MQTT client")
        return eventgrid_client
    except Exception as e:
        logger.error(f"Failed to initialize Event Grid MQTT client: {e}")
        return None


def on_eventgrid_connect(client, userdata, flags, rc):
    """Callback when the Event Grid MQTT client connects."""
    if rc == 0:
        logger.info(f"Connected to Event Grid MQTT broker at {EVENTGRID_MQTT_HOSTNAME}:{EVENTGRID_MQTT_PORT}")
    else:
        logger.error(f"Failed to connect to Event Grid MQTT broker, return code {rc}")


def on_eventgrid_disconnect(client, userdata, rc):
    """Callback when the Event Grid MQTT client disconnects."""
    if rc != 0:
        logger.warning(f"Unexpected disconnection from Event Grid MQTT broker, return code {rc}")


def augment_message(payload):
    """
    Augment the message with additional data.
    Adds timestamp and processing metadata.
    """
    try:
        # Parse the original message
        message = json.loads(payload) if isinstance(payload, str) else payload
        
        # Add timestamp and metadata
        augmented = {
            'original_data': message,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'processed_by': 'mqtt-proxy',
            'source': 'on-premises-mqtt'
        }
        
        return augmented
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse message as JSON: {e}")
        # If not JSON, wrap the raw payload
        return {
            'original_data': payload,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'processed_by': 'mqtt-proxy',
            'source': 'on-premises-mqtt'
        }


def send_to_eventgrid(augmented_data):
    """Send augmented data to Azure Event Grid MQTT broker."""
    if eventgrid_client is None:
        logger.info(f"Test mode - would send to Event Grid: {json.dumps(augmented_data, indent=2)}")
        return True
    
    try:
        # Convert to JSON string
        payload = json.dumps(augmented_data)
        
        # Publish to Event Grid MQTT broker
        result = eventgrid_client.publish(EVENTGRID_MQTT_TOPIC, payload, qos=1)
        
        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            logger.info(f"Successfully sent message to Event Grid MQTT topic: {EVENTGRID_MQTT_TOPIC}")
            return True
        else:
            logger.error(f"Failed to publish to Event Grid MQTT, return code {result.rc}")
            return False
        
    except Exception as e:
        logger.error(f"Failed to send to Event Grid MQTT: {e}")
        return False


def on_local_connect(client, userdata, flags, rc):
    """Callback when the client receives a CONNACK response from the local broker."""
    if rc == 0:
        logger.info(f"Connected to local MQTT broker at {LOCAL_MQTT_BROKER}:{LOCAL_MQTT_PORT}")
        # Subscribe to topic
        client.subscribe(LOCAL_MQTT_TOPIC, qos=1)
        logger.info(f"Subscribed to topic: {LOCAL_MQTT_TOPIC}")
    else:
        logger.error(f"Failed to connect to local MQTT broker, return code {rc}")


def on_message(client, userdata, msg):
    """Callback when a PUBLISH message is received from the local broker."""
    try:
        logger.info(f"Received message on topic {msg.topic}")
        
        # Decode payload
        payload = msg.payload.decode('utf-8')
        logger.debug(f"Payload: {payload[:200]}...")
        
        # Augment the message
        augmented_data = augment_message(payload)
        logger.info(f"Augmented message with timestamp: {augmented_data.get('timestamp')}")
        
        # Send to Azure Event Grid MQTT broker
        success = send_to_eventgrid(augmented_data)
        
        if success:
            logger.info("Message processed and forwarded successfully")
        else:
            logger.error("Failed to forward message to Event Grid")
            
    except Exception as e:
        logger.error(f"Error processing message: {e}", exc_info=True)


def on_local_disconnect(client, userdata, rc):
    """Callback when the client disconnects from the local broker."""
    if rc != 0:
        logger.warning(f"Unexpected disconnection from local broker, return code {rc}")


def main():
    """Main function to run the MQTT proxy."""
    global local_client
    
    logger.info("Starting MQTT to Azure Event Grid MQTT Broker Proxy")
    
    # Initialize Event Grid MQTT client
    init_eventgrid_mqtt_client()
    
    # Create local MQTT client
    local_client = mqtt.Client(client_id="mqtt-proxy_subscriber")
    local_client.on_connect = on_local_connect
    local_client.on_message = on_message
    local_client.on_disconnect = on_local_disconnect
    
    # Connect to local broker
    try:
        logger.info(f"Connecting to local MQTT broker at {LOCAL_MQTT_BROKER}:{LOCAL_MQTT_PORT}")
        local_client.connect(LOCAL_MQTT_BROKER, LOCAL_MQTT_PORT, 60)
        
        # Start the loop
        logger.info("Starting MQTT loop")
        local_client.loop_forever()
        
    except KeyboardInterrupt:
        logger.info("Shutting down proxy")
    except Exception as e:
        logger.error(f"Error in main loop: {e}", exc_info=True)
    finally:
        local_client.disconnect()
        if eventgrid_client:
            eventgrid_client.loop_stop()
            eventgrid_client.disconnect()


if __name__ == "__main__":
    main()
