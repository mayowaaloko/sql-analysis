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

 
-- CREATE CLEAN VIEW
CREATE OR REPLACE VIEW v_clean_rides AS
SELECT 

    -- Service identification
    hvfhs_license_num,
    CASE
        WHEN hvfhs_license_num = 'HV0003' THEN 'Uber'
        WHEN hvfhs_license_num = 'HV0005' THEN 'Lyft'
        ELSE 'Other'
    END as service_name,
    dispatching_base_num,
    originating_base_num,
    -- Timestamps
    request_datetime,
    on_scene_datetime,
    pickup_datetime,
    dropoff_datetime,
    -- Location information
    "PULocationID" as pickup_location_id,
    "DOLocationID" as dropoff_location_id,
    -- Trip metrics
    trip_miles,
    trip_time,
    ROUND((trip_time / 60.0)::numeric, 2) as trip_duration_minutes,
  
    -- Financial information
    base_passenger_fare,
    COALESCE(tolls, 0) as tolls,
    COALESCE(bcf, 0) as bcf,
    COALESCE(sales_tax, 0) as sales_tax,
    COALESCE(congestion_surcharge, 0) as congestion_surcharge,
    COALESCE(airport_fee, 0) as airport_fee,
    COALESCE(tips, 0) as tips,
    COALESCE(driver_pay, 0) as driver_pay,
    COALESCE(cbd_congestion_fee, 0) as cbd_congestion_fee,
    -- Calculate total revenue
    base_passenger_fare + COALESCE(tips, 0) + COALESCE(tolls, 0) + COALESCE(congestion_surcharge, 0) + COALESCE(airport_fee, 0) + COALESCE(cbd_congestion_fee, 0) as total_revenue,
    -- Trip characteristics
    COALESCE(shared_request_flag, 'N') as shared_request_flag,
    COALESCE(shared_match_flag, 'N') as shared_match_flag,
    COALESCE(access_a_ride_flag, 'N') as access_a_ride_flag,
    COALESCE(wav_request_flag, 'N') as wav_request_flag,
    COALESCE(wav_match_flag, 'N') as wav_match_flag
FROM raw_rides -- Your original data quality filters
WHERE pickup_datetime >= '2025-01-01'
    AND pickup_datetime < '2025-07-01'
    AND dropoff_datetime > pickup_datetime
    AND "PULocationID" IS NOT NULL
    AND "DOLocationID" IS NOT NULL
    AND "PULocationID" > 0
    AND "DOLocationID" > 0
    AND trip_miles > 0
    AND trip_time > 0
    AND base_passenger_fare > 0
    AND hvfhs_license_num IN ('HV0003', 'HV0005');
-- Verify the view is ready
SELECT 'v_clean_rides view created successfully' as status;

-- VERIFY CLEANING RESULTS (UPDATED FOR VIEW)

-- Check average fare vs total revenue via the View
SELECT 'Average base fare' as metric,
    ROUND(AVG(base_passenger_fare)::numeric, 2) as value
FROM v_clean_rides
UNION ALL
SELECT 'Average total revenue',
    ROUND(AVG(total_revenue)::numeric, 2)
FROM v_clean_rides;