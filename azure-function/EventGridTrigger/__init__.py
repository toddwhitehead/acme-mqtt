"""
Azure Function to receive Event Grid messages and store in Blob Storage
"""

import json
import logging
import os
import time
from datetime import datetime, timezone
import azure.functions as func
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import ResourceNotFoundError, ResourceModifiedError
from azure.core import MatchConditions

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
                
                # Retry logic to handle concurrent modifications
                max_retries = 5
                retry_count = 0
                success = False
                
                while not success and retry_count < max_retries:
                    try:
                        # Read existing events or start with empty list
                        events_list = []
                        etag = None
                        try:
                            # Try to download existing blob
                            blob_properties = blob_client.download_blob()
                            existing_content = blob_properties.readall().decode('utf-8')
                            events_list = json.loads(existing_content)
                            etag = blob_properties.properties.etag
                            logging.info(f"Loaded {len(events_list)} existing events from {blob_name}")
                        except ResourceNotFoundError:
                            # Blob doesn't exist yet, start with empty list
                            logging.info(f"No existing file found, creating new daily file: {blob_name}")
                        
                        # Append new event to the list
                        events_list.append(blob_data)
                        
                        # Upload updated list back to blob with ETag for concurrency control
                        # If etag is provided, upload will fail if the blob was modified by another process
                        upload_kwargs = {'overwrite': True}
                        if etag:
                            upload_kwargs['etag'] = etag
                            upload_kwargs['match_condition'] = MatchConditions.IfNotModified
                        
                        blob_client.upload_blob(
                            json.dumps(events_list, indent=2),
                            **upload_kwargs
                        )
                        
                        logging.info(f"Successfully appended event to {blob_name}. Total events: {len(events_list)}")
                        success = True
                        
                    except ResourceModifiedError as e:
                        # ETag mismatch - retry with backoff
                        retry_count += 1
                        if retry_count < max_retries:
                            wait_time = (2 ** retry_count) * 0.1  # Exponential backoff: 0.2s, 0.4s, 0.8s, 1.6s
                            logging.warning(f"Concurrent modification detected, retrying in {wait_time}s (attempt {retry_count}/{max_retries})")
                            time.sleep(wait_time)
                        else:
                            logging.error(f"Failed to upload after {max_retries} retries due to concurrent modifications")
                            raise
                    except Exception as e:
                        # Check if it's a condition not met error (alternative way Azure SDK reports ETag mismatch)
                        if 'ConditionNotMet' in str(e):
                            retry_count += 1
                            if retry_count < max_retries:
                                wait_time = (2 ** retry_count) * 0.1  # Exponential backoff
                                logging.warning(f"Concurrent modification detected, retrying in {wait_time}s (attempt {retry_count}/{max_retries})")
                                time.sleep(wait_time)
                            else:
                                logging.error(f"Failed to upload after {max_retries} retries due to concurrent modifications")
                                raise
                        else:
                            # Other exceptions should not be retried
                            raise
                
            except Exception as e:
                logging.error(f"Error storing data in blob storage: {e}")
                raise
        else:
            logging.warning("Blob connection string not configured. Data not stored.")
            logging.info(f"Would append to daily file: {json.dumps(blob_data, indent=2)}")
        
    except Exception as e:
        logging.error(f"Error processing Event Grid event: {e}", exc_info=True)
        raise
