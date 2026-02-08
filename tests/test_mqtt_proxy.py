"""
Unit tests for MQTT proxy message augmentation
"""

import json
import sys
import os
from datetime import datetime

# Add parent directory to path to import mqtt_proxy
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'mqtt-proxy'))

from mqtt_proxy import augment_message


def test_augment_json_message():
    """Test augmentation of JSON message"""
    original_message = {
        "sensor_id": "sensor_01",
        "value": 22.5,
        "unit": "celsius"
    }
    
    payload = json.dumps(original_message)
    augmented = augment_message(payload)
    
    # Check that original data is preserved
    assert augmented['original_data'] == original_message
    
    # Check that metadata is added
    assert 'timestamp' in augmented
    assert augmented['processed_by'] == 'mqtt-proxy'
    assert augmented['source'] == 'on-premises-mqtt'
    
    # Check timestamp format (ISO 8601)
    timestamp = augmented['timestamp']
    datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
    
    print("✓ test_augment_json_message passed")


def test_augment_string_message():
    """Test augmentation of non-JSON string message"""
    payload = "Simple text message"
    augmented = augment_message(payload)
    
    # Check that raw payload is wrapped
    assert augmented['original_data'] == payload
    
    # Check that metadata is added
    assert 'timestamp' in augmented
    assert augmented['processed_by'] == 'mqtt-proxy'
    assert augmented['source'] == 'on-premises-mqtt'
    
    print("✓ test_augment_string_message passed")


def test_augment_complex_message():
    """Test augmentation of complex nested JSON message"""
    original_message = {
        "device": {
            "id": "device_01",
            "location": {
                "lat": 40.7128,
                "lon": -74.0060
            }
        },
        "readings": [
            {"type": "temp", "value": 22.5},
            {"type": "humidity", "value": 65.2}
        ]
    }
    
    payload = json.dumps(original_message)
    augmented = augment_message(payload)
    
    # Check that original nested structure is preserved
    assert augmented['original_data'] == original_message
    assert augmented['original_data']['device']['id'] == "device_01"
    assert len(augmented['original_data']['readings']) == 2
    
    print("✓ test_augment_complex_message passed")


if __name__ == "__main__":
    print("Running MQTT proxy tests...\n")
    
    try:
        test_augment_json_message()
        test_augment_string_message()
        test_augment_complex_message()
        
        print("\n✅ All tests passed!")
        sys.exit(0)
        
    except AssertionError as e:
        print(f"\n❌ Test failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error running tests: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
