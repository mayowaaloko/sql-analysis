import os
import requests
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# PostgreSQL config
DB_HOST = os.getenv('DB_HOST')
DB_PORT = os.getenv('DB_PORT')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

# Data config
BASE_URL = os.getenv('BASE_URL')
YEAR = int(os.getenv('YEAR'))
END_MONTH = int(os.getenv('END_MONTH'))

# Chunk sizes
CHUNK_SIZE = 500_000   # number of rows read from parquet at a time
TO_SQL_CHUNK = 5000    # number of rows per insert to PostgreSQL

print("="*70)
print(f"NYC FHVHV (Uber/Lyft) Data Extraction - {YEAR}")
print("="*70)

# Step 1: Connect to database
engine = create_engine(f'postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}')

# Step 2: Find last date loaded
with engine.connect() as conn:
    result = conn.execute(text("SELECT MAX(dropoff_datetime) FROM raw_rides"))
    last_date = result.scalar()

if last_date:
    start_month = last_date.month
    print(f"Resuming import from last loaded date: {last_date}")
else:
    start_month = 1
    print("No existing data found. Starting from January")

# Step 3: Loop through months
total_rows_loaded = 0
for month in range(start_month, END_MONTH + 1):
    month_str = f"{month:02d}"
    filename = f"fhvhv_tripdata_{YEAR}-{month_str}.parquet"
    url = f"{BASE_URL}/{filename}"

    print(f"\n📅 Processing {YEAR}-{month_str}...")

    try:
        # Download parquet
        response = requests.get(url, stream=True)
        if response.status_code != 200:
            print(f"Data not available for {YEAR}-{month_str}, skipping...")
            continue

        temp_file = f"temp_{filename}"
        with open(temp_file, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)

        file_size_mb = os.path.getsize(temp_file) / (1024*1024)
        print(f"Downloaded {filename} ({file_size_mb:.1f} MB)")

        # Read parquet file
        parquet_df = pd.read_parquet(temp_file)
        total_rows = len(parquet_df)
        month_rows_loaded = 0

        # If resuming, skip rows already loaded
        if last_date and month == start_month:
            parquet_df = parquet_df[parquet_df['dropoff_datetime'] > last_date]
            print(f"Starting import from: {parquet_df['dropoff_datetime'].min()}")

        # Process in chunks
        for start_idx in range(0, len(parquet_df), CHUNK_SIZE):
            chunk_df = parquet_df.iloc[start_idx:start_idx+CHUNK_SIZE]

            # Insert to PostgreSQL in smaller batches
            chunk_df.to_sql(
                'raw_rides',
                engine,
                if_exists='append',
                index=False,
                method='multi',
                chunksize=TO_SQL_CHUNK
            )

            month_rows_loaded += len(chunk_df)
            total_rows_loaded += len(chunk_df)
            progress = (month_rows_loaded / len(parquet_df)) * 100
            print(f"   Progress: {month_rows_loaded:,}/{len(parquet_df):,} rows ({progress:.1f}%)")

            # Clean memory
            del chunk_df

        # Clean up
        del parquet_df
        os.remove(temp_file)

        print(f"✅ Month {month_str} complete! ({month_rows_loaded:,} rows loaded)")

    except Exception as e:
        print(f"⚠️  Error processing month {month_str}: {e}")
        if os.path.exists(temp_file):
            os.remove(temp_file)
        continue

print("\n" + "="*70)
print(f"✅ DATA IMPORT COMPLETE!")
print(f"   Total rows loaded this run: {total_rows_loaded:,}")
print("="*70)
