"""
Azure Function to receive Event Grid messages and store in Blob Storage
"""

import json
import logging
import os
from datetime import datetime, timezone
import azure.functions as func
from azure.storage.blob import BlobServiceClient

# Get blob storage connection string from environment
BLOB_CONNECTION_STRING = os.getenv('AzureWebJobsStorage')
BLOB_CONTAINER_NAME = os.getenv('BLOB_CONTAINER_NAME', 'mqtt-data')


def main(event: func.EventGridEvent):
    """
    Main function triggered by Event Grid events.
    Receives MQTT data from Event Grid and stores it in Blob Storage.
    """
    logging.info('Python EventGrid trigger function processed an event')
    
    try:
        # Parse event data
        event_data = event.get_json()
        event_id = event.id
        event_type = event.event_type
        event_subject = event.subject
        event_time = event.event_time
        
        logging.info(f"Event ID: {event_id}")
        logging.info(f"Event Type: {event_type}")
        logging.info(f"Event Subject: {event_subject}")
        logging.info(f"Event Time: {event_time}")
        
        # Create blob name based on date (one file per day)
        date_str = datetime.now(timezone.utc).strftime('%Y-%m-%d')
        blob_name = f"events_{date_str}.json"
        
        # Prepare data to store
        blob_data = {
            'event_id': event_id,
            'event_type': event_type,
            'event_subject': event_subject,
            'event_time': str(event_time),
            'data': event_data,
            'stored_at': datetime.now(timezone.utc).isoformat()
        }
        
        # Store in blob storage
        if BLOB_CONNECTION_STRING:
            try:
                blob_service_client = BlobServiceClient.from_connection_string(
                    BLOB_CONNECTION_STRING
                )
                
                # Get or create container
                container_client = blob_service_client.get_container_client(
                    BLOB_CONTAINER_NAME
                )
                
                # Create container if it doesn't exist
                try:
                    container_client.create_container()
                    logging.info(f"Created container: {BLOB_CONTAINER_NAME}")
                except Exception:
                    # Container already exists
                    pass
                
                # Get blob client
                blob_client = container_client.get_blob_client(blob_name)
                
                # Read existing events or start with empty list
                events_list = []
                try:
                    # Try to download existing blob
                    blob_data_stream = blob_client.download_blob()
                    existing_content = blob_data_stream.readall().decode('utf-8')
                    events_list = json.loads(existing_content)
                    logging.info(f"Loaded {len(events_list)} existing events from {blob_name}")
                except Exception as e:
                    # Blob doesn't exist yet, start with empty list
                    logging.info(f"No existing file found, creating new daily file: {blob_name}")
                
                # Append new event to the list
                events_list.append(blob_data)
                
                # Upload updated list back to blob
                blob_client.upload_blob(
                    json.dumps(events_list, indent=2),
                    overwrite=True
                )
                
                logging.info(f"Successfully appended event to {blob_name}. Total events: {len(events_list)}")
                
            except Exception as e:
                logging.error(f"Error storing data in blob storage: {e}")
                raise
        else:
            logging.warning("Blob connection string not configured. Data not stored.")
            logging.info(f"Would append to daily file: {json.dumps(blob_data, indent=2)}")
        
    except Exception as e:
        logging.error(f"Error processing Event Grid event: {e}", exc_info=True)
        raise
