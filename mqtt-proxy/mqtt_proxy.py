#!/usr/bin/env python3
"""
MQTT to Azure Event Grid Proxy
Subscribes to MQTT broker, augments messages with timestamp, and publishes to Azure Event Grid.
"""

import json
import os
import logging
from datetime import datetime, timezone
import paho.mqtt.client as mqtt
from azure.core.credentials import AzureKeyCredential
from azure.eventgrid import EventGridPublisherClient
from azure.core.messaging import CloudEvent

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment variables
MQTT_BROKER = os.getenv('MQTT_BROKER', 'mqtt-broker')
MQTT_PORT = int(os.getenv('MQTT_PORT', 1883))
MQTT_TOPIC = os.getenv('MQTT_TOPIC', 'sensor/data')

# Azure Event Grid configuration
EVENTGRID_ENDPOINT = os.getenv('EVENTGRID_ENDPOINT', '')
EVENTGRID_KEY = os.getenv('EVENTGRID_KEY', '')
EVENTGRID_TOPIC_HOSTNAME = os.getenv('EVENTGRID_TOPIC_HOSTNAME', '')

# Event Grid client
eventgrid_client = None


def init_eventgrid_client():
    """Initialize Azure Event Grid client."""
    global eventgrid_client
    
    if not EVENTGRID_ENDPOINT or not EVENTGRID_KEY:
        logger.warning("Azure Event Grid credentials not configured. Running in test mode.")
        return None
    
    try:
        credential = AzureKeyCredential(EVENTGRID_KEY)
        eventgrid_client = EventGridPublisherClient(EVENTGRID_ENDPOINT, credential)
        logger.info(f"Initialized Event Grid client for endpoint: {EVENTGRID_ENDPOINT}")
        return eventgrid_client
    except Exception as e:
        logger.error(f"Failed to initialize Event Grid client: {e}")
        return None


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
    """Send augmented data to Azure Event Grid."""
    if eventgrid_client is None:
        logger.info(f"Test mode - would send to Event Grid: {json.dumps(augmented_data, indent=2)}")
        return True
    
    try:
        # Create CloudEvent
        event = CloudEvent(
            type="AcmeMqtt.SensorData",
            source="acme-mqtt-proxy",
            data=augmented_data
        )
        
        # Send to Event Grid
        eventgrid_client.send([event])
        logger.info(f"Successfully sent event to Event Grid")
        return True
        
    except Exception as e:
        logger.error(f"Failed to send to Event Grid: {e}")
        return False


def on_connect(client, userdata, flags, rc):
    """Callback when the client receives a CONNACK response from the server."""
    if rc == 0:
        logger.info(f"Connected to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
        # Subscribe to topic
        client.subscribe(MQTT_TOPIC, qos=1)
        logger.info(f"Subscribed to topic: {MQTT_TOPIC}")
    else:
        logger.error(f"Failed to connect to MQTT broker, return code {rc}")


def on_message(client, userdata, msg):
    """Callback when a PUBLISH message is received from the broker."""
    try:
        logger.info(f"Received message on topic {msg.topic}")
        
        # Decode payload
        payload = msg.payload.decode('utf-8')
        logger.debug(f"Payload: {payload[:200]}...")
        
        # Augment the message
        augmented_data = augment_message(payload)
        logger.info(f"Augmented message with timestamp: {augmented_data.get('timestamp')}")
        
        # Send to Azure Event Grid
        success = send_to_eventgrid(augmented_data)
        
        if success:
            logger.info("Message processed and forwarded successfully")
        else:
            logger.error("Failed to forward message to Event Grid")
            
    except Exception as e:
        logger.error(f"Error processing message: {e}", exc_info=True)


def on_disconnect(client, userdata, rc):
    """Callback when the client disconnects from the broker."""
    if rc != 0:
        logger.warning(f"Unexpected disconnection, return code {rc}")


def main():
    """Main function to run the MQTT proxy."""
    logger.info("Starting MQTT to Azure Event Grid Proxy")
    
    # Initialize Event Grid client
    init_eventgrid_client()
    
    # Create MQTT client
    client = mqtt.Client(client_id="mqtt_proxy")
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect
    
    # Connect to broker
    try:
        logger.info(f"Connecting to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
        
        # Start the loop
        logger.info("Starting MQTT loop")
        client.loop_forever()
        
    except KeyboardInterrupt:
        logger.info("Shutting down proxy")
    except Exception as e:
        logger.error(f"Error in main loop: {e}", exc_info=True)
    finally:
        client.disconnect()


if __name__ == "__main__":
    main()
