# Onprem Component - Sample Data

This directory contains sample bird detection event data files from an AI-powered camera system deployed in a backyard in Brisbane, Australia.

## Data Format

The detection events are stored as individual JSON files, one per bird detection event. Each file follows a consistent schema designed for MQTT transmission and processing.

### File Naming Convention

Files are named using the pattern: `bird_detection_YYYYMMDD_HHMMSS.json`

Example: `bird_detection_20260208_063015.json`

### Data Schema

Each JSON file contains the following fields:

#### Top-Level Fields
- `event_id` (string): Unique identifier for the detection event
- `timestamp` (string): ISO 8601 timestamp with timezone (AEST/AEDT +10:00)
- `camera_id` (string): Identifier for the camera that captured the event

#### Location Object
- `city` (string): City name
- `state` (string): State/territory
- `country` (string): Country
- `coordinates` (object): GPS coordinates
  - `latitude` (number): Latitude in decimal degrees
  - `longitude` (number): Longitude in decimal degrees
- `zone` (string): Specific area within the location (e.g., "backyard")

#### Detection Object
- `object_type` (string): Type of object detected (always "bird" for these samples)
- `species` (string): Full species name
- `common_name` (string): Common name of the species
- `scientific_name` (string): Scientific/Latin name
- `confidence` (number): AI model confidence score (0.0 to 1.0)
- `bounding_box` (object): Object location in the image
  - `x_min`, `y_min`: Top-left corner coordinates
  - `x_max`, `y_max`: Bottom-right corner coordinates
  - `width`, `height`: Bounding box dimensions in pixels
- `image_dimensions` (object): Original image size
  - `width` (number): Image width in pixels
  - `height` (number): Image height in pixels

#### Environmental Data Object
- `temperature_celsius` (number): Temperature in degrees Celsius
- `humidity_percent` (number): Relative humidity percentage
- `light_level` (string): Light conditions (dawn, morning, full_sun, afternoon, dusk, evening)
- `weather` (string): Weather description

#### AI Model Object
- `name` (string): Name of the AI model used
- `version` (string): Model version
- `provider` (string): Model provider/vendor

## Sample Bird Species

The sample data includes common Australian bird species found in Brisbane backyards:

1. **Australian Magpie** (*Gymnorhina tibicen*) - A large black and white bird, known for its beautiful caroling song
2. **Laughing Kookaburra** (*Dacelo novaeguineae*) - Famous for its distinctive laughing call
3. **Rainbow Lorikeet** (*Trichoglossus moluccanus*) - Colorful parrot with bright plumage
4. **Noisy Miner** (*Manorina melanocephala*) - Territorial native honeyeater
5. **Australian White Ibis** (*Threskiornis moluccus*) - Large wading bird, locally nicknamed "Bin Chicken"
6. **Sulphur-crested Cockatoo** (*Cacatua galerita*) - Large white parrot with yellow crest
7. **Pied Currawong** (*Strepera graculina*) - Large black bird with yellow eyes
8. **Australian Brush Turkey** (*Alectura lathami*) - Large ground-dwelling bird

## Time Range

Sample detections span a full day (February 8, 2026) from early morning (6:30 AM) through evening (7:21 PM), representing typical bird activity patterns in Brisbane.

## Usage

These sample files can be used for:
- Testing MQTT message processing pipelines
- Developing data analytics and visualization tools
- Training machine learning models
- Simulating real-time bird detection events
- Testing data ingestion and storage systems

## MQTT Integration

When transmitted via MQTT, these events would typically be:
- Published to topics like: `acme/camera/{camera_id}/detection/bird`
- Sent with QoS level 1 (at least once delivery)
- Include additional metadata in MQTT headers if needed
