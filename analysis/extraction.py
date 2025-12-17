import os
import requests
import pandas as pd
from sqlalchemy import create_engine
from dotenv import load_dotenv
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

# Load environment variables
load_dotenv()

# Configuration from .env
DB_HOST = os.getenv('DB_HOST')
DB_PORT = os.getenv('DB_PORT')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')
BASE_URL = os.getenv('BASE_URL')
YEAR = int(os.getenv('YEAR'))
START_MONTH = int(os.getenv('START_MONTH'))
END_MONTH = int(os.getenv('END_MONTH'))

# Chunk size for reading large parquet files
CHUNK_SIZE = 500000  # Process 500k rows at a time

print("=" * 70)
print(f"NYC FHVHV (Uber/Lyft) Data Extraction - {YEAR} Q1-Q2")
print("=" * 70)

# Step 1: Create database if it doesn't exist
print(f"\n[1/3] Checking if database '{DB_NAME}' exists...")
try:
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database='postgres'
    )
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()
    
    cur.execute(f"SELECT 1 FROM pg_database WHERE datname = '{DB_NAME}'")
    exists = cur.fetchone()
    
    if not exists:
        cur.execute(f"CREATE DATABASE {DB_NAME}")
        print(f"✅ Database '{DB_NAME}' created successfully!")
    else:
        print(f"✅ Database '{DB_NAME}' already exists.")
    
    cur.close()
    conn.close()
except Exception as e:
    print(f"❌ Error creating database: {e}")
    exit(1)

# Step 2: Create SQLAlchemy engine
print(f"\n[2/3] Connecting to '{DB_NAME}'...")
try:
    engine = create_engine(
        f'postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}'
    )
    print("✅ Connected to PostgreSQL!")
except Exception as e:
    print(f"❌ Error connecting to database: {e}")
    exit(1)

# Step 3: Download and load data month by month
print(f"\n[3/3] Downloading and loading data for months {START_MONTH}-{END_MONTH}...")
print("-" * 70)

total_rows_loaded = 0

for month in range(START_MONTH, END_MONTH + 1):
    month_str = f"{month:02d}"
    filename = f"fhvhv_tripdata_{YEAR}-{month_str}.parquet"
    url = f"{BASE_URL}/{filename}"
    
    print(f"\n📅 Processing {YEAR}-{month_str}...")
    
    try:
        # Download file
        print(f"   ⬇️  Downloading {filename}...", end=" ")
        response = requests.get(url, stream=True)
        
        if response.status_code != 200:
            print(f"\n   ❌ Server returned {response.status_code}. Data not available.")
            if response.status_code in [403, 404]:
                print(f"   🛑 Stopping - data for {month_str}/{YEAR} not released yet.")
                break
            continue
        
        # Save temporarily
        temp_file = f"temp_{filename}"
        with open(temp_file, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        file_size_mb = os.path.getsize(temp_file) / (1024 * 1024)
        print(f"✓ ({file_size_mb:.1f} MB)")
        
        # Read and load in chunks
        print(f"   📖 Loading in chunks of {CHUNK_SIZE:,} rows...")
        
        parquet_file = pd.read_parquet(temp_file)
        total_rows = len(parquet_file)
        month_rows_loaded = 0
        
        # Process in chunks
        for start_idx in range(0, total_rows, CHUNK_SIZE):
            end_idx = min(start_idx + CHUNK_SIZE, total_rows)
            chunk_df = parquet_file.iloc[start_idx:end_idx]
            
            # Load chunk to PostgreSQL
            chunk_df.to_sql(
                'raw_rides',
                engine,
                if_exists='append',
                index=False,
                method='multi',
                chunksize=10000
            )
            
            month_rows_loaded += len(chunk_df)
            progress = (month_rows_loaded / total_rows) * 100
            print(f"      Progress: {month_rows_loaded:,}/{total_rows:,} rows ({progress:.1f}%)")
            
            # Clear chunk from memory
            del chunk_df
        
        # Clear main dataframe
        del parquet_file
        
        # Remove temporary file
        os.remove(temp_file)
        
        total_rows_loaded += month_rows_loaded
        print(f"   ✅ Month {month_str} complete! ({month_rows_loaded:,} rows loaded)")
        
    except Exception as e:
        print(f"\n   ⚠️  Error processing month {month_str}: {e}")
        if os.path.exists(temp_file):
            os.remove(temp_file)
        continue

print("\n" + "=" * 70)
print(f"✅ EXTRACTION COMPLETE!")
print(f"   Total rows loaded: {total_rows_loaded:,}")
print(f"   Database: {DB_NAME}")
print(f"   Table: raw_rides")
print("=" * 70)


