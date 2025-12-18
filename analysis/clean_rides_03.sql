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







CREATE TABLE pbi_master_fact AS
SELECT 
    DATE(pickup_datetime) as ride_date,
    EXTRACT(DOW FROM pickup_datetime) as day_of_week,
    EXTRACT(HOUR FROM pickup_datetime) as hour_of_day,
    service_name,
    pickup_location_id,
    dropoff_location_id,
    'Short (<2mi)'::text as distance_category,
    0::bigint as total_trips,
    0::numeric as total_revenue,
    0::numeric as total_base_fare,
    0::numeric as total_tips,
    0::numeric as total_tolls,
    0::numeric as total_congestion,
    0::numeric as total_airport_fees,
    0::numeric as total_miles,
    0::numeric as total_minutes,
    0::numeric as avg_fare,
    0::numeric as avg_distance,
    0::numeric as avg_duration,
    0::bigint as shared_requested,
    0::bigint as shared_matched,
    0::bigint as wav_requested,
    0::bigint as wav_matched
FROM v_clean_rides LIMIT 0;



INSERT INTO pbi_master_fact
SELECT 
    DATE(pickup_datetime), EXTRACT(DOW FROM pickup_datetime), EXTRACT(HOUR FROM pickup_datetime),
    service_name, pickup_location_id, dropoff_location_id,
    CASE WHEN trip_miles < 2 THEN 'Short (<2mi)' WHEN trip_miles BETWEEN 2 AND 5 THEN 'Medium (2-5mi)' ELSE 'Long (>5mi)' END,
    COUNT(*), SUM(total_revenue), SUM(base_passenger_fare), SUM(tips), SUM(tolls), SUM(congestion_surcharge), SUM(airport_fee), SUM(trip_miles), SUM(trip_time / 60.0),
    ROUND(AVG(base_passenger_fare)::numeric, 2), ROUND(AVG(trip_miles)::numeric, 2), ROUND(AVG(trip_time / 60.0)::numeric, 2),
    SUM(CASE WHEN shared_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN shared_match_flag = 'Y' THEN 1 ELSE 0 END),
    SUM(CASE WHEN wav_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN wav_match_flag = 'Y' THEN 1 ELSE 0 END)
FROM v_clean_rides
WHERE pickup_datetime >= '2025-01-01' AND pickup_datetime < '2025-02-01'
GROUP BY 1, 2, 3, 4, 5, 6, 7;


INSERT INTO pbi_master_fact
SELECT 
    DATE(pickup_datetime), EXTRACT(DOW FROM pickup_datetime), EXTRACT(HOUR FROM pickup_datetime),
    service_name, pickup_location_id, dropoff_location_id,
    CASE WHEN trip_miles < 2 THEN 'Short (<2mi)' WHEN trip_miles BETWEEN 2 AND 5 THEN 'Medium (2-5mi)' ELSE 'Long (>5mi)' END,
    COUNT(*), SUM(total_revenue), SUM(base_passenger_fare), SUM(tips), SUM(tolls), SUM(congestion_surcharge), SUM(airport_fee), SUM(trip_miles), SUM(trip_time / 60.0),
    ROUND(AVG(base_passenger_fare)::numeric, 2), ROUND(AVG(trip_miles)::numeric, 2), ROUND(AVG(trip_time / 60.0)::numeric, 2),
    SUM(CASE WHEN shared_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN shared_match_flag = 'Y' THEN 1 ELSE 0 END),
    SUM(CASE WHEN wav_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN wav_match_flag = 'Y' THEN 1 ELSE 0 END)
FROM v_clean_rides
WHERE pickup_datetime >= '2025-02-01' AND pickup_datetime < '2025-03-01'
GROUP BY 1, 2, 3, 4, 5, 6, 7;



INSERT INTO pbi_master_fact
SELECT 
    DATE(pickup_datetime), EXTRACT(DOW FROM pickup_datetime), EXTRACT(HOUR FROM pickup_datetime),
    service_name, pickup_location_id, dropoff_location_id,
    CASE WHEN trip_miles < 2 THEN 'Short (<2mi)' WHEN trip_miles BETWEEN 2 AND 5 THEN 'Medium (2-5mi)' ELSE 'Long (>5mi)' END,
    COUNT(*), SUM(total_revenue), SUM(base_passenger_fare), SUM(tips), SUM(tolls), SUM(congestion_surcharge), SUM(airport_fee), SUM(trip_miles), SUM(trip_time / 60.0),
    ROUND(AVG(base_passenger_fare)::numeric, 2), ROUND(AVG(trip_miles)::numeric, 2), ROUND(AVG(trip_time / 60.0)::numeric, 2),
    SUM(CASE WHEN shared_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN shared_match_flag = 'Y' THEN 1 ELSE 0 END),
    SUM(CASE WHEN wav_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN wav_match_flag = 'Y' THEN 1 ELSE 0 END)
FROM v_clean_rides
WHERE pickup_datetime >= '2025-03-01' AND pickup_datetime < '2025-04-01'
GROUP BY 1, 2, 3, 4, 5, 6, 7;



INSERT INTO pbi_master_fact
SELECT 
    DATE(pickup_datetime), EXTRACT(DOW FROM pickup_datetime), EXTRACT(HOUR FROM pickup_datetime),
    service_name, pickup_location_id, dropoff_location_id,
    CASE WHEN trip_miles < 2 THEN 'Short (<2mi)' WHEN trip_miles BETWEEN 2 AND 5 THEN 'Medium (2-5mi)' ELSE 'Long (>5mi)' END,
    COUNT(*), SUM(total_revenue), SUM(base_passenger_fare), SUM(tips), SUM(tolls), SUM(congestion_surcharge), SUM(airport_fee), SUM(trip_miles), SUM(trip_time / 60.0),
    ROUND(AVG(base_passenger_fare)::numeric, 2), ROUND(AVG(trip_miles)::numeric, 2), ROUND(AVG(trip_time / 60.0)::numeric, 2),
    SUM(CASE WHEN shared_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN shared_match_flag = 'Y' THEN 1 ELSE 0 END),
    SUM(CASE WHEN wav_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN wav_match_flag = 'Y' THEN 1 ELSE 0 END)
FROM v_clean_rides
WHERE pickup_datetime >= '2025-04-01' AND pickup_datetime < '2025-05-01'
GROUP BY 1, 2, 3, 4, 5, 6, 7;


INSERT INTO pbi_master_fact
SELECT 
    DATE(pickup_datetime), EXTRACT(DOW FROM pickup_datetime), EXTRACT(HOUR FROM pickup_datetime),
    service_name, pickup_location_id, dropoff_location_id,
    CASE WHEN trip_miles < 2 THEN 'Short (<2mi)' WHEN trip_miles BETWEEN 2 AND 5 THEN 'Medium (2-5mi)' ELSE 'Long (>5mi)' END,
    COUNT(*), SUM(total_revenue), SUM(base_passenger_fare), SUM(tips), SUM(tolls), SUM(congestion_surcharge), SUM(airport_fee), SUM(trip_miles), SUM(trip_time / 60.0),
    ROUND(AVG(base_passenger_fare)::numeric, 2), ROUND(AVG(trip_miles)::numeric, 2), ROUND(AVG(trip_time / 60.0)::numeric, 2),
    SUM(CASE WHEN shared_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN shared_match_flag = 'Y' THEN 1 ELSE 0 END),
    SUM(CASE WHEN wav_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN wav_match_flag = 'Y' THEN 1 ELSE 0 END)
FROM v_clean_rides
WHERE pickup_datetime >= '2025-05-01' AND pickup_datetime < '2025-06-01'
GROUP BY 1, 2, 3, 4, 5, 6, 7;



INSERT INTO pbi_master_fact
SELECT 
    DATE(pickup_datetime), EXTRACT(DOW FROM pickup_datetime), EXTRACT(HOUR FROM pickup_datetime),
    service_name, pickup_location_id, dropoff_location_id,
    CASE WHEN trip_miles < 2 THEN 'Short (<2mi)' WHEN trip_miles BETWEEN 2 AND 5 THEN 'Medium (2-5mi)' ELSE 'Long (>5mi)' END,
    COUNT(*), SUM(total_revenue), SUM(base_passenger_fare), SUM(tips), SUM(tolls), SUM(congestion_surcharge), SUM(airport_fee), SUM(trip_miles), SUM(trip_time / 60.0),
    ROUND(AVG(base_passenger_fare)::numeric, 2), ROUND(AVG(trip_miles)::numeric, 2), ROUND(AVG(trip_time / 60.0)::numeric, 2),
    SUM(CASE WHEN shared_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN shared_match_flag = 'Y' THEN 1 ELSE 0 END),
    SUM(CASE WHEN wav_request_flag = 'Y' THEN 1 ELSE 0 END), SUM(CASE WHEN wav_match_flag = 'Y' THEN 1 ELSE 0 END)
FROM v_clean_rides
WHERE pickup_datetime >= '2025-06-01' AND pickup_datetime < '2025-07-01'
GROUP BY 1, 2, 3, 4, 5, 6, 7;



CREATE INDEX idx_pbi_date ON pbi_master_fact(ride_date);
CREATE INDEX idx_pbi_service ON pbi_master_fact(service_name);
CREATE INDEX idx_pbi_pickup ON pbi_master_fact(pickup_location_id);
CREATE INDEX idx_pbi_dropoff ON pbi_master_fact(dropoff_location_id);
CREATE INDEX idx_pbi_day_of_week ON pbi_master_fact(day_of_week);
CREATE INDEX idx_pbi_hour ON pbi_master_fact(hour_of_day);


SELECT 
    TO_CHAR(ride_date, 'YYYY-MM') as month, 
    COUNT(*) as aggregated_rows, 
    SUM(total_trips) as actual_rides 
FROM pbi_master_fact 
GROUP BY 1 
ORDER BY 1;