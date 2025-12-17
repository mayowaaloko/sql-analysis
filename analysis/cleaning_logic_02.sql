
/*
INSPECTION FINDINGS SUMMARY:
- Total trips: 120,827,156
- Date range: Jan 1 - July 1, 2025 (575k trips outside expected H1 range)
- Services: 72.64% Uber (HV0003), 27.36% Lyft (HV0005)
- Issues found:
  1. 575,124 trips outside Jan-June 2025 range
  2. 32.9M NULL originating_base_num (27% of data)
  3. 10.8M NULL on_scene_datetime (9% of data)
  4. 14,845 trips with zero/negative miles
  5. 110,711 trips with zero/negative fares
  6. 41,805 suspicious trips (< 0.1 miles but > 30 min)
  7. Some extreme outliers (518 miles, $1691 fare)
  8. Only 7 exact duplicates (negligible)
*/


-- Test date filtering (remove trips outside Jan-June 2025)
-- Question: How many trips fall outside our target date range?
-- Decision: We'll filter these out since we only want H1 2025 data
SELECT 
    CASE 
        WHEN pickup_datetime >= '2025-01-01' AND pickup_datetime < '2025-07-01' THEN 'Valid Range'
        ELSE 'Outside Range'
    END as date_validity,
    COUNT(*) as trip_count
FROM raw_rides
GROUP BY date_validity;


-- Test service provider standardization
-- Question: Are there any unknown license numbers we need to handle?
-- Decision: Map license numbers to readable service names
SELECT 
    hvfhs_license_num as original_license,
    CASE 
        WHEN hvfhs_license_num = 'HV0003' THEN 'Uber'
        WHEN hvfhs_license_num = 'HV0005' THEN 'Lyft'
        ELSE 'Other'
    END as service_name,
    COUNT(*) as trip_count
FROM raw_rides
GROUP BY hvfhs_license_num
ORDER BY trip_count DESC;



-- Test trip distance cleaning (remove zero/negative miles)
-- Question: What percentage of trips have invalid distances?
-- Decision: Filter out trips with miles <= 0; keep extreme distances (might be legit long trips)
SELECT 
    CASE 
        WHEN trip_miles IS NULL THEN 'NULL distance'
        WHEN trip_miles <= 0 THEN 'Zero or negative'
        WHEN trip_miles > 0 AND trip_miles <= 100 THEN 'Valid distance'
        WHEN trip_miles > 100 THEN 'Extreme distance (> 100 miles)'
    END as distance_category,
    COUNT(*) as trip_count,
    ROUND(AVG(trip_miles)::numeric, 2) as avg_miles
FROM raw_rides
GROUP BY distance_category
ORDER BY trip_count DESC;



-- Test fare cleaning (remove zero/negative fares)
-- Question: What does the fare distribution look like after removing invalid values?
-- Decision: Filter out trips with fare <= 0; keep high fares (might be airport/long trips)
SELECT 
    CASE 
        WHEN base_passenger_fare IS NULL THEN 'NULL fare'
        WHEN base_passenger_fare <= 0 THEN 'Zero or negative'
        WHEN base_passenger_fare > 0 AND base_passenger_fare <= 500 THEN 'Normal fare'
        WHEN base_passenger_fare > 500 THEN 'Very high fare (> $500)'
    END as fare_category,
    COUNT(*) as trip_count,
    ROUND(AVG(base_passenger_fare)::NUMERIC, 2) as avg_fare
FROM raw_rides
GROUP BY fare_category
ORDER BY trip_count DESC;




-- test trip time validation (remove zero/negative durations)
-- Question: Are there trips with impossible durations?
-- Decision: Filter out trips with time <= 0
SELECT 
    CASE 
        WHEN trip_time IS NULL THEN 'NULL duration'
        WHEN trip_time <= 0 THEN 'Zero or negative'
        WHEN trip_time > 0 AND trip_time <= 7200 THEN 'Normal duration (< 2 hours)'
        WHEN trip_time > 7200 THEN 'Very long duration (> 2 hours)'
    END as duration_category,
    COUNT(*) as trip_count,
    ROUND(AVG(trip_time / 60.0)::NUMERIC, 2) as avg_minutes
FROM raw_rides
GROUP BY duration_category
ORDER BY trip_count DESC;



-- Test location validation (check for NULL or invalid zone IDs)
-- Question: How many trips have missing location data?
-- Decision: Filter out trips with missing pickup or dropoff locations
SELECT 
    CASE 
        WHEN "PULocationID" IS NULL OR "DOLocationID" IS NULL THEN 'Missing locations'
        WHEN "PULocationID" = 0 OR "DOLocationID" = 0 THEN 'Zero location ID'
        WHEN "PULocationID" > 0 AND "DOLocationID" > 0 THEN 'Valid locations'
    END as location_validity,
    COUNT(*) as trip_count
FROM raw_rides
GROUP BY location_validity
ORDER BY trip_count DESC;


-- Test calculated total revenue field
-- Question: Can we calculate total revenue properly including all fee components?
-- Decision: Use COALESCE to treat NULL fees as 0
SELECT 
    base_passenger_fare,
    COALESCE(tips, 0) as tips_clean,
    COALESCE(tolls, 0) as tolls_clean,
    COALESCE(congestion_surcharge, 0) as congestion_clean,
    COALESCE(airport_fee, 0) as airport_fee_clean,
    -- Calculate total revenue (fare + all fees and tips)
    base_passenger_fare + 
    COALESCE(tips, 0) + 
    COALESCE(tolls, 0) + 
    COALESCE(congestion_surcharge, 0) + 
    COALESCE(airport_fee, 0) as total_revenue
FROM raw_rides
WHERE base_passenger_fare > 0
LIMIT 100;



-- Test suspicious trip identification
-- Question: How should we handle very short trips with long durations?
-- Decision: Keep these trips - might be traffic jams, but they're real trips with valid fares

SELECT 
    pickup_datetime,
    trip_miles,
    trip_time / 60 as trip_minutes,
    base_passenger_fare,
    CASE 
        WHEN trip_miles < 0.1 AND trip_time > 1800 THEN 'Suspicious (short distance, long time)'
        ELSE 'Normal'
    END as trip_validity
FROM raw_rides
WHERE trip_miles < 0.1 AND trip_time > 1800
LIMIT 50;



-- ============================================================================
-- STEP 4: RUN THE CLEANING PROCEDURE
-- Execute the procedure to populate clean_rides table
-- ============================================================================

-- Clear any existing data in clean_rides (if re-running)
TRUNCATE TABLE clean_rides;

-- Run the cleaning procedure
CALL sp_clean_rides();

-- This will take several minutes due to the large dataset (120M rows)
-- Expected result: ~119M rows inserted (after filtering out invalid records)


-- ============================================================================
-- STEP 5: VERIFY CLEANING RESULTS
-- Check that cleaned data meets our quality standards
-- ============================================================================

-- 5.1: Verify row count
SELECT 
    'Total rows in clean_rides' as metric,
    COUNT(*) as value
FROM clean_rides;
-- Expected: Around 119-120M rows (after removing ~1M invalid records)


-- 5.2: Verify date range
SELECT 
    'Date range' as metric,
    MIN(pickup_datetime)::TEXT || ' to ' || MAX(pickup_datetime)::TEXT as value
FROM clean_rides;
-- Expected: 2025-01-01 to 2025-06-30 (no dates outside this range)


-- 5.3: Verify no invalid distances
SELECT 
    'Trips with distance <= 0' as metric,
    COUNT(*) as value
FROM clean_rides
WHERE trip_miles <= 0;
-- Expected: 0 (all should be filtered out)


-- 5.4: Verify no invalid fares
SELECT 
    'Trips with fare <= 0' as metric,
    COUNT(*) as value
FROM clean_rides
WHERE base_passenger_fare <= 0;
-- Expected: 0 (all should be filtered out)


-- 5.5: Verify service distribution
SELECT 
    service_name,
    COUNT(*) as trip_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM clean_rides
GROUP BY service_name;
-- Expected: ~73% Uber, ~27% Lyft (same as raw data)


-- 5.6: Verify total revenue calculation
SELECT 
    'Average base fare' as metric,
    ROUND(AVG(base_passenger_fare), 2) as value
FROM clean_rides

UNION ALL

SELECT 
    'Average total revenue',
    ROUND(AVG(total_revenue), 2)
FROM clean_rides;
-- Expected: Total revenue should be higher than base fare (includes tips, tolls, fees)


-- 5.7: Compare before and after counts
SELECT 
    'Raw rides count' as dataset,
    COUNT(*) as trip_count
FROM raw_rides
WHERE pickup_datetime >= '2025-01-01' AND pickup_datetime < '2025-07-01'

UNION ALL

SELECT 
    'Clean rides count',
    COUNT(*)
FROM clean_rides;
-- Purpose: See how many rows were filtered out during cleaning


-- ============================================================================
-- STEP 6: CREATE TRIGGER FOR AUTOMATIC CLEANING
-- When new data is loaded into raw_rides, automatically clean it
-- ============================================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION trigger_clean_rides()
RETURNS TRIGGER AS $$
BEGIN
    -- Call the cleaning procedure whenever new data is inserted
    CALL sp_clean_rides();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger to raw_rides table
DROP TRIGGER IF EXISTS after_insert_raw_rides ON raw_rides;

CREATE TRIGGER after_insert_raw_rides
AFTER INSERT ON raw_rides
FOR EACH STATEMENT
EXECUTE FUNCTION trigger_clean_rides();

-- Verify trigger was created
SELECT 'Trigger created: New raw data will automatically be cleaned' as status;


-- ============================================================================
-- SUMMARY REPORT
-- ============================================================================

SELECT 
    '============================================' as summary_report
UNION ALL
SELECT 'DATA CLEANING COMPLETE'
UNION ALL
SELECT '============================================'
UNION ALL
SELECT 'Raw data: ' || (SELECT COUNT(*)::TEXT FROM raw_rides) || ' trips'
UNION ALL
SELECT 'Clean data: ' || (SELECT COUNT(*)::TEXT FROM clean_rides) || ' trips'
UNION ALL
SELECT 'Removed: ' || (SELECT (COUNT(*) - (SELECT COUNT(*) FROM clean_rides))::TEXT FROM raw_rides) || ' invalid trips'
UNION ALL
SELECT '============================================'
UNION ALL
SELECT 'Ready for Phase 4: Data Modeling & Aggregation';
