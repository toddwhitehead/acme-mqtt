#!/usr/bin/env python3
"""
MQTT Test Client
Reads test data files and publishes messages to the MQTT broker.
"""

import json
import time
import os
import glob
import logging
from pathlib import Path
import paho.mqtt.client as mqtt

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
TEST_DATA_DIR = os.getenv('TEST_DATA_DIR', '/app/test-data')
PUBLISH_INTERVAL = int(os.getenv('PUBLISH_INTERVAL', 5))  # seconds


def on_connect(client, userdata, flags, rc):
    """Callback for when the client receives a CONNACK response from the server."""
    if rc == 0:
        logger.info(f"Connected to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
    else:
        logger.error(f"Failed to connect to MQTT broker, return code {rc}")


def on_publish(client, userdata, mid):
    """Callback for when a message is published."""
    logger.debug(f"Message {mid} published successfully")


def load_test_data():
    """Load test data from JSON files in the test-data directory."""
    test_files = glob.glob(os.path.join(TEST_DATA_DIR, '*.json'))
    
    if not test_files:
        logger.warning(f"No test data files found in {TEST_DATA_DIR}")
        return []
    
    all_data = []
    for file_path in test_files:
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
                if isinstance(data, list):
                    all_data.extend(data)
                else:
                    all_data.append(data)
            logger.info(f"Loaded test data from {file_path}")
        except Exception as e:
            logger.error(f"Error loading {file_path}: {e}")
    
    return all_data


def main():
    """Main function to publish test messages."""
    logger.info("Starting MQTT Test Client")
    
    # Create MQTT client
    client = mqtt.Client(client_id="test_client")
    client.on_connect = on_connect
    client.on_publish = on_publish
    
    # Connect to broker
    try:
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
        client.loop_start()
    except Exception as e:
        logger.error(f"Failed to connect to MQTT broker: {e}")
        return
    
    # Load test data
    test_data = load_test_data()
    
    if not test_data:
        logger.error("No test data available. Exiting.")
        return
    
    logger.info(f"Loaded {len(test_data)} test messages")
    
    # Publish messages in a loop
    message_index = 0
    try:
        while True:
            # Get next message (cycle through test data)
            message = test_data[message_index % len(test_data)]
            message_index += 1
            
            # Convert to JSON string
            payload = json.dumps(message)
            
            # Publish message
            result = client.publish(MQTT_TOPIC, payload, qos=1)
            
            if result.rc == mqtt.MQTT_ERR_SUCCESS:
                logger.info(f"Published message #{message_index}: {payload[:100]}...")
            else:
                logger.error(f"Failed to publish message, return code {result.rc}")
            
            # Wait before next publish
            time.sleep(PUBLISH_INTERVAL)
            
    except KeyboardInterrupt:
        logger.info("Shutting down test client")
    finally:
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    main()
