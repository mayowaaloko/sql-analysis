SELECT *
FROM raw_rides
LIMIT 100;
--  WHat is the total number of trips?
SELECT COUNT(*) as total_trips
FROM raw_rides;
-- Are there any dates outside this range (2025-01-01 to 2025-06-30?
SELECT MIN(pickup_datetime) as earliest_pick,
    MAX(dropoff_datetime) as latest_pick
FROM raw_rides;
-- Which columns have a lot of NULLs?
SELECT COUNT(*) as total_rows,
    -- License and base information
    COUNT(*) - COUNT(hvfhs_license_num) as null_license,
    COUNT(*) - COUNT(dispatching_base_num) as null_dispatching_base,
    COUNT(*) - COUNT(originating_base_num) as null_originating_base,
    -- Date/time columns
    COUNT(*) - COUNT(request_datetime) as null_request_time,
    COUNT(*) - COUNT(on_scene_datetime) as null_on_scene_time,
    COUNT(*) - COUNT(pickup_datetime) as null_pickup_time,
    COUNT(*) - COUNT(dropoff_datetime) as null_dropoff_time,
    -- Location columns
    COUNT(*) - COUNT("PULocationID") as null_pickup_location,
    COUNT(*) - COUNT("DOLocationID") as null_dropoff_location,
    -- Trip details
    COUNT(*) - COUNT(trip_miles) as null_trip_miles,
    COUNT(*) - COUNT(trip_time) as null_trip_time,
    -- Money columns
    COUNT(*) - COUNT(base_passenger_fare) as null_fare,
    COUNT(*) - COUNT(tolls) as null_tolls,
    COUNT(*) - COUNT(bcf) as null_bcf,
    COUNT(*) - COUNT(sales_tax) as null_sales_tax,
    COUNT(*) - COUNT(congestion_surcharge) as null_congestion,
    COUNT(*) - COUNT(airport_fee) as null_airport_fee,
    COUNT(*) - COUNT(tips) as null_tips,
    COUNT(*) - COUNT(driver_pay) as null_driver_pay,
    -- Flag columns
    COUNT(*) - COUNT(shared_request_flag) as null_shared_request,
    COUNT(*) - COUNT(shared_match_flag) as null_shared_match,
    COUNT(*) - COUNT(access_a_ride_flag) as null_access_a_ride,
    COUNT(*) - COUNT(wav_request_flag) as null_wav_request,
    COUNT(*) - COUNT(wav_match_flag) as null_wav_match,
    COUNT(*) - COUNT(cbd_congestion_fee) as null_cbd_fee
FROM raw_rides;
-- Check unique license numbers (this tells us the service providers)
-- HV0003 (Uber), HV0005 (Lyft)
SELECT hvfhs_license_num,
    COUNT(*) as trip_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM raw_rides
GROUP BY hvfhs_license_num
ORDER BY trip_count DESC;
-- Any trips with pickup date outside expected range?
SELECT COUNT(*) as trips_outside_range
FROM raw_rides
WHERE pickup_datetime < '2025-01-01'
    OR pickup_datetime > '2025-06-30';
-- Are there trips where dropoff is BEFORE pickup?
SELECT COUNT(*) as impossible_trips
FROM raw_rides
WHERE dropoff_datetime < pickup_datetime;
-- it is clean
-- Check distribution of trips by month
-- Is any month way lower or higher than others?
SELECT TO_CHAR(pickup_datetime, 'YYYY-MM') as month,
    COUNT(*) as trips
FROM raw_rides
GROUP BY TO_CHAR(pickup_datetime, 'YYYY-MM')
ORDER BY month;
-- Check trips by day of week
SELECT TO_CHAR(pickup_datetime, 'Day') as day_of_week,
    COUNT(*) as trips
FROM raw_rides
GROUP BY TO_CHAR(pickup_datetime, 'Day')
ORDER BY trips DESC;
-- Count unique pickup and dropoff locations
SELECT COUNT(DISTINCT "PULocationID") as unique_pickup_locations
FROM raw_rides;
SELECT COUNT(DISTINCT "DOLocationID") as unique_dropoff_locations
FROM raw_rides;
-- Check for the most common pickup locations
SELECT "PULocationID",
    COUNT(*) as pickup_count
FROM raw_rides
GROUP BY "PULocationID"
ORDER BY pickup_count DESC
LIMIT 20;
-- Check for NULL or zero location IDs
SELECT COUNT(*) as trips_with_missing_locations
FROM raw_rides
WHERE "PULocationID" IS NULL
    OR "DOLocationID" IS NULL
    OR "PULocationID" = 0
    OR "DOLocationID" = 0;
-- Basic statistics on trip distance
SELECT MIN(trip_miles) as shortest_trip,
    MAX(trip_miles) as longest_trip,
    AVG(trip_miles) as average_trip,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY trip_miles
    ) as median_trip
FROM raw_rides
WHERE trip_miles IS NOT NULL;
-- Are there trips with 0 seconds?
SELECT MIN(trip_time) as shortest_trip,
    MAX(trip_time) as longest_trip,
    AVG(trip_time) as average_trip,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY trip_time
    ) as median_trip
FROM raw_rides
WHERE trip_time IS NOT NULL;
-- Check for suspicious trips (very short distance but long time)
SELECT COUNT(*) as suspicious_trips
FROM raw_rides
WHERE trip_miles < 0.1 -- Check for negative or zero values
SELECT COUNT(*) as zero_or_negative_miles
FROM raw_rides
WHERE trip_miles <= 0;
-- Check trip time distribution
SELECT CASE
        WHEN trip_time < 300 THEN 'Under 5 min'
        WHEN trip_time BETWEEN 300 AND 600 THEN '5-10 min'
        WHEN trip_time BETWEEN 600 AND 1200 THEN '10-20 min'
        WHEN trip_time BETWEEN 1200 AND 1800 THEN '20-30 min'
        WHEN trip_time BETWEEN 1800 AND 3600 THEN '30-60 min'
        ELSE 'Over 1 hour'
    END as time_range,
    COUNT(*) as trip_count
FROM raw_rides
WHERE trip_time IS NOT NULL
GROUP BY time_range
ORDER BY trip_count DESC;
-- Are there negative fares?
SELECT MIN(base_passenger_fare) as min_fare,
    MAX(base_passenger_fare) as max_fare,
    AVG(base_passenger_fare) as avg_fare,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY base_passenger_fare
    ) as median_fare
FROM raw_rides
WHERE base_passenger_fare IS NOT NULL;
-- Check for zero or negative fares
SELECT COUNT(*) as trips_with_zero_or_negative_fare
FROM raw_rides
WHERE base_passenger_fare <= 0;
-- Does tips amount make sense compared to base fare?
SELECT SUM(base_passenger_fare) as total_base_fare,
    SUM(tolls) as total_tolls,
    SUM(tips) as total_tips,
    SUM(congestion_surcharge) as total_congestion,
    SUM(airport_fee) as total_airport_fees,
    SUM(sales_tax) as total_sales_tax
FROM raw_rides;
-- Calculate fare per mile
SELECT AVG(base_passenger_fare / NULLIF(trip_miles, 0)) as avg_fare_per_mile
FROM raw_rides
WHERE trip_miles > 0
    AND base_passenger_fare > 0;
-- Check tip percentage distribution. Do tipping patterns look normal?
SELECT CASE
        WHEN tips = 0
        OR tips IS NULL THEN 'No tip'
        WHEN (tips / NULLIF(base_passenger_fare, 0)) < 0.10 THEN 'Under 10%'
        WHEN (tips / NULLIF(base_passenger_fare, 0)) BETWEEN 0.10 AND 0.20 THEN '10-20%'
        WHEN (tips / NULLIF(base_passenger_fare, 0)) BETWEEN 0.20 AND 0.30 THEN '20-30%'
        ELSE 'Over 30%'
    END as tip_range,
    COUNT(*) as trip_count
FROM raw_rides
WHERE base_passenger_fare > 0
GROUP BY tip_range
ORDER BY trip_count DESC;
-- Count shared rides, What percentage requested sharing?
SELECT shared_request_flag,
    COUNT(*) as trip_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM raw_rides
GROUP BY shared_request_flag;
-- Count matched shared rides
SELECT shared_match_flag,
    COUNT(*) as trip_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM raw_rides
GROUP BY shared_match_flag;
--checking if those who requested sharing, how many got matched?
--Wheelchair accessible vehicle requests and matches to See demand for and supply of wheelchair accessible vehicles
SELECT wav_request_flag as requested_wheelchair,
    wav_match_flag as got_wheelchair,
    COUNT(*) as trip_count
FROM raw_rides
GROUP BY wav_request_flag,
    wav_match_flag;
-- How many trips are Access-A-Ride (ADA paratransit)?
SELECT access_a_ride_flag,
    COUNT(*) as trip_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM raw_rides
GROUP BY access_a_ride_flag;
--Check for exact duplicate rows
SELECT (
        SELECT COUNT(*)
        FROM raw_rides
    ) - (
        SELECT COUNT(*)
        FROM (
                SELECT DISTINCT hvfhs_license_num,
                    pickup_datetime,
                    dropoff_datetime,
                    "PULocationID",
                    "DOLocationID",
                    base_passenger_fare
                FROM raw_rides
            ) t
    ) as duplicate_rows;
FROM raw_rides;
-- Find potential duplicate trips (same time, location, fare), are they real duplicates or just coincidences?
SELECT pickup_datetime,
    "PULocationID",
    "DOLocationID",
    base_passenger_fare,
    COUNT(*) as duplicate_count
FROM raw_rides
GROUP BY pickup_datetime,
    "PULocationID",
    "DOLocationID",
    base_passenger_fare
HAVING COUNT(*) > 1
LIMIT 100;
-- Check if all datetime columns are actually timestamps
SELECT COUNT(*) as trips_with_invalid_dates
FROM raw_rides
WHERE pickup_datetime IS NOT NULL
    AND NOT (pickup_datetime::TEXT ~ '^\d{4}-\d{2}-\d{2}');
--Check for weird characters in text columns
SELECT DISTINCT hvfhs_license_num
FROM raw_rides
ORDER BY hvfhs_license_num;
SELECT DISTINCT dispatching_base_num
FROM raw_rides
ORDER BY dispatching_base_num;
SELECT DISTINCT originating_base_num
FROM raw_rides
ORDER BY originating_base_num;
-- Find extremely expensive trips, Are these legitimate (long airport trips) or errors?
SELECT pickup_datetime,
    "PULocationID",
    "DOLocationID",
    trip_miles,
    trip_time,
    base_passenger_fare,
    tips,
    base_passenger_fare + tips as total_charge
FROM raw_rides
WHERE base_passenger_fare > 500
ORDER BY base_passenger_fare DESC
LIMIT 20;
-- Find extremely long trips
SELECT pickup_datetime,
    "PULocationID",
    "DOLocationID",
    trip_miles,
    trip_time / 60 as trip_minutes,
    base_passenger_fare
FROM raw_rides
WHERE trip_miles > 100
ORDER BY trip_miles DESC
LIMIT 20;
-- Find trips with very high fare per mile,  Why are some trips over $20/mile? (traffic? surge pricing?)
SELECT trip_miles,
    base_passenger_fare,
    trip_time / 60 as trip_minutes,
    base_passenger_fare / NULLIF(trip_miles, 0) as fare_per_mile
FROM raw_rides
WHERE trip_miles > 1 -- Filter out short trips to avoid 'minimum fare' skew
    AND base_passenger_fare / NULLIF(trip_miles, 0) > 20
ORDER BY fare_per_mile DESC
LIMIT 20;