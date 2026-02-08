FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY test_client.py .

# Copy test data directory
COPY ../test-data /app/test-data

CMD ["python", "test_client.py"]
