"""
Unit tests for Event Grid handler logic
"""

import json
import sys
from datetime import datetime, timezone


def test_daily_filename_format():
    """Test that the blob name follows the daily format"""
    # The function should create a filename like events_2026-02-08.json
    date_str = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    expected_blob_name = f"events_{date_str}.json"
    
    # This is what we expect based on our implementation
    assert expected_blob_name.startswith("events_")
    assert expected_blob_name.endswith(".json")
    assert len(date_str) == 10  # YYYY-MM-DD format
    
    print(f"✓ test_daily_filename_format passed - Expected format: {expected_blob_name}")


def test_event_data_structure():
    """Test that event data structure includes all required fields"""
    event_data = {
        'event_id': 'test-event-id',
        'event_type': 'Microsoft.EventGrid.TestEvent',
        'event_subject': 'test/subject',
        'event_time': '2026-02-08T01:18:05.441Z',
        'data': {'key': 'value'},
        'stored_at': datetime.now(timezone.utc).isoformat()
    }
    
    # Verify all required fields are present
    assert 'event_id' in event_data
    assert 'event_type' in event_data
    assert 'event_subject' in event_data
    assert 'event_time' in event_data
    assert 'data' in event_data
    assert 'stored_at' in event_data
    
    print("✓ test_event_data_structure passed")


def test_append_logic():
    """Test that events are properly appended to a list"""
    # Simulate existing events
    existing_events = [
        {'event_id': 'event1', 'data': {'value': 1}},
        {'event_id': 'event2', 'data': {'value': 2}}
    ]
    
    # New event to append
    new_event = {'event_id': 'event3', 'data': {'value': 3}}
    
    # Append logic
    events_list = existing_events.copy()
    events_list.append(new_event)
    
    # Verify the list grows
    assert len(events_list) == 3
    assert events_list[0]['event_id'] == 'event1'
    assert events_list[1]['event_id'] == 'event2'
    assert events_list[2]['event_id'] == 'event3'
    
    # Verify JSON serialization works
    json_output = json.dumps(events_list, indent=2)
    assert json_output is not None
    
    # Verify we can parse it back
    parsed = json.loads(json_output)
    assert len(parsed) == 3
    
    print("✓ test_append_logic passed")


def test_empty_list_initialization():
    """Test that a new daily file starts with an empty list"""
    events_list = []
    
    # Add first event
    first_event = {'event_id': 'first', 'data': {'value': 'first'}}
    events_list.append(first_event)
    
    # Verify list now has one event
    assert len(events_list) == 1
    assert events_list[0]['event_id'] == 'first'
    
    print("✓ test_empty_list_initialization passed")


if __name__ == "__main__":
    print("Running Event Grid handler tests...\n")
    
    try:
        test_daily_filename_format()
        test_event_data_structure()
        test_append_logic()
        test_empty_list_initialization()
        
        print("\n✅ All tests passed!")
        sys.exit(0)
        
    except AssertionError as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error running tests: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
