
-- ============================================================================
-- SECTION 1: BUSINESS QUESTION VIEWS (For Documentation & Analysis)
-- These views answer the 15 key business questions
-- ============================================================================

-- ----------------------------------------------------------------------------
-- REVENUE & GROWTH QUESTIONS
-- ----------------------------------------------------------------------------

-- Q1: What's total revenue for H1 2025?
CREATE OR REPLACE VIEW vw_q1_total_revenue AS
SELECT 
    'H1 2025' as period,
    COUNT(*) as total_trips,
    SUM(total_revenue) as total_revenue,
    AVG(base_passenger_fare) as avg_base_fare,
    SUM(tips) as total_tips,
    SUM(tolls) as total_tolls
FROM v_clean_rides;

SELECT *
FROM vw_q1_total_revenue;


-- Q2: What's the month-over-month revenue growth?
CREATE OR REPLACE VIEW vw_q2_monthly_growth AS
WITH monthly_revenue AS (
    SELECT 
        DATE_TRUNC('month', pickup_datetime) as month,
        SUM(total_revenue) as revenue,
        COUNT(*) as trips
    FROM v_clean_rides
    GROUP BY DATE_TRUNC('month', pickup_datetime)
)
SELECT 
    TO_CHAR(month, 'YYYY-MM') as month,
    revenue,
    trips,
    LAG(revenue) OVER (ORDER BY month) as prev_month_revenue,
    ROUND(
        ((revenue - LAG(revenue) OVER (ORDER BY month)) / 
         NULLIF(LAG(revenue) OVER (ORDER BY month), 0) * 100)::numeric, 
        2
    ) as growth_percentage
FROM monthly_revenue
ORDER BY month;

SELECT *
FROM vw_q2_monthly_growth;
-- Shows month-by-month revenue with % growth from previous month


-- Q3: Which service (Uber/Lyft) generates more revenue?
CREATE OR REPLACE VIEW vw_q3_service_revenue AS
SELECT 
    service_name,
    COUNT(*) as total_trips,
    SUM(total_revenue) as total_revenue,
    AVG(base_passenger_fare) as avg_fare,
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ())::numeric, 2) as market_share_trips,
    ROUND((SUM(total_revenue) * 100.0 / SUM(SUM(total_revenue)) OVER ())::numeric, 2) as market_share_revenue
FROM v_clean_rides
GROUP BY service_name
ORDER BY total_revenue DESC;

SELECT *
FROM vw_q3_service_revenue;
-- Shows Uber vs Lyft total revenue and market share


-- Q4: What's the revenue trend (growing/declining)?
CREATE OR REPLACE VIEW vw_q4_revenue_trend AS
SELECT 
    DATE(pickup_datetime) as date,
    SUM(total_revenue) as daily_revenue,
    COUNT(*) as daily_trips,
    AVG(base_passenger_fare) as avg_fare
FROM v_clean_rides
GROUP BY DATE(pickup_datetime)
ORDER BY date;

SELECT *
FROM vw_q4_revenue_trend;
-- Daily revenue trend - use this for trend line charts


-- ----------------------------------------------------------------------------
-- OPERATIONAL EFFICIENCY QUESTIONS (5-8)
-- ----------------------------------------------------------------------------

-- Q5: What's the average trip distance and duration?
CREATE OR REPLACE VIEW vw_q5_trip_metrics AS
SELECT 
    'H1 2025' as period,
    ROUND(AVG(trip_miles)::numeric, 2) as avg_distance_miles,
    ROUND(AVG(trip_duration_minutes)::numeric, 2) as avg_duration_minutes,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY trip_miles)::numeric, 2) as median_distance,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY trip_duration_minutes)::numeric, 2) as median_duration,
    MIN(trip_miles) as shortest_trip,
    MAX(trip_miles) as longest_trip
FROM v_clean_rides;

SELECT *
FROM vw_q5_trip_metrics;
-- Overall trip efficiency metrics


-- Q6: What hours/days have highest demand?
CREATE OR REPLACE VIEW vw_q6_demand_patterns AS
SELECT 
    EXTRACT(DOW FROM pickup_datetime) as day_of_week,
    TO_CHAR(pickup_datetime, 'Day') as day_name,
    EXTRACT(HOUR FROM pickup_datetime) as hour_of_day,
    COUNT(*) as trip_count,
    SUM(total_revenue) as revenue,
    AVG(base_passenger_fare) as avg_fare
FROM v_clean_rides
GROUP BY 
    EXTRACT(DOW FROM pickup_datetime),
    TO_CHAR(pickup_datetime, 'Day'),
    EXTRACT(HOUR FROM pickup_datetime)
ORDER BY day_of_week, hour_of_day;

SELECT *
FROM vw_q6_demand_patterns;


-- Q7: How many rides per driver on average?
CREATE OR REPLACE VIEW vw_q7_driver_activity AS
WITH driver_stats AS (
    SELECT 
        dispatching_base_num,
        COUNT(*) as trips_per_driver
    FROM v_clean_rides
    WHERE dispatching_base_num IS NOT NULL
    GROUP BY dispatching_base_num
)
SELECT 
    COUNT(DISTINCT dispatching_base_num) as total_active_drivers,
    ROUND(AVG(trips_per_driver)::numeric, 2) as avg_trips_per_driver,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY trips_per_driver)::numeric, 2) as median_trips_per_driver,
    MIN(trips_per_driver) as min_trips,
    MAX(trips_per_driver) as max_trips
FROM driver_stats;

SELECT *
FROM vw_q7_driver_activity;
-- Driver utilization summary


-- Q8: What's the average fare per mile?
CREATE OR REPLACE VIEW vw_q8_fare_per_mile AS
SELECT 
    'H1 2025' as period,
    ROUND((SUM(base_passenger_fare) / NULLIF(SUM(trip_miles), 0))::numeric, 2) as avg_fare_per_mile,
    ROUND(AVG(base_passenger_fare / NULLIF(trip_miles, 0))::numeric, 2) as avg_fare_per_mile_by_trip
FROM v_clean_rides
WHERE trip_miles > 0;

SELECT *
FROM vw_q8_fare_per_mile;
-- Pricing efficiency metric


-- ----------------------------------------------------------------------------
-- GEOGRAPHIC PERFORMANCE QUESTIONS (9-12)
-- ----------------------------------------------------------------------------

-- Q9: Which pickup zones generate most revenue?
CREATE OR REPLACE VIEW vw_q9_top_pickup_zones AS
SELECT 
    z.zone as pickup_zone,
    z.borough,
    COUNT(*) as total_trips,
    SUM(r.total_revenue) as total_revenue,
    AVG(r.base_passenger_fare) as avg_fare,
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ())::numeric, 2) as pct_of_total_trips
FROM v_clean_rides r
JOIN dim_zones z ON r.pickup_location_id = z.location_id
GROUP BY z.zone, z.borough
ORDER BY total_revenue DESC
LIMIT 50;

SELECT *
FROM vw_q9_top_pickup_zones;
-- Top 50 zones by revenue for map visualization


-- Q10: Which zones are growing fastest? (Jan to June)
CREATE OR REPLACE VIEW vw_q10_zone_growth AS
WITH zone_monthly AS (
    SELECT 
        pickup_location_id,
        DATE_TRUNC('month', pickup_datetime) as month,
        SUM(total_revenue) as revenue
    FROM v_clean_rides
    GROUP BY pickup_location_id, DATE_TRUNC('month', pickup_datetime)
),
first_last_month AS (
    SELECT 
        pickup_location_id,
        MAX(CASE WHEN month = '2025-01-01' THEN revenue END) as jan_revenue,
        MAX(CASE WHEN month = '2025-06-01' THEN revenue END) as june_revenue
    FROM zone_monthly
    GROUP BY pickup_location_id
)
SELECT 
    z.zone as pickup_zone,
    z.borough,
    f.jan_revenue,
    f.june_revenue,
    ROUND(
        ((f.june_revenue - f.jan_revenue) / NULLIF(f.jan_revenue, 0) * 100)::numeric, 
        2
    ) as growth_percentage
FROM first_last_month f
JOIN dim_zones z ON f.pickup_location_id = z.location_id
WHERE f.jan_revenue IS NOT NULL AND f.june_revenue IS NOT NULL
ORDER BY growth_percentage DESC
LIMIT 20;

SELECT *
FROM vw_q10_zone_growth;
-- Top 20 fastest growing zones (Jan to June)


-- Q11: What are the most common pickup → dropoff routes?
CREATE OR REPLACE VIEW vw_q11_top_routes AS
SELECT 
    pz.zone as pickup_neighborhood,
    dz.zone as dropoff_neighborhood,
    COUNT(*) as trip_count,
    SUM(r.total_revenue) as total_revenue,
    AVG(r.trip_miles) as avg_distance,
    AVG(r.trip_duration_minutes) as avg_duration
FROM v_clean_rides r
JOIN dim_zones pz ON r.pickup_location_id = pz.location_id
JOIN dim_zones dz ON r.dropoff_location_id = dz.location_id
GROUP BY pz.zone, dz.zone
ORDER BY trip_count DESC
LIMIT 100;

SELECT *
FROM vw_q11_top_routes;
-- Top 100 most popular routes


-- Q12: Are there underserved zones with potential?
CREATE OR REPLACE VIEW vw_q12_underserved_zones AS
WITH zone_stats AS (
    SELECT 
        pickup_location_id,
        COUNT(*) as pickup_count,
        AVG(base_passenger_fare) as avg_fare
    FROM v_clean_rides
    GROUP BY pickup_location_id
),
zone_ranking AS (
    SELECT 
        pickup_location_id,
        pickup_count,
        avg_fare,
        NTILE(4) OVER (ORDER BY pickup_count) as demand_quartile,
        NTILE(4) OVER (ORDER BY avg_fare) as fare_quartile
    FROM zone_stats
)
SELECT 
    z.zone as pickup_zone,
    z.borough,
    zr.pickup_count,
    ROUND(zr.avg_fare::numeric, 2) as avg_fare,
    CASE 
        WHEN demand_quartile <= 2 AND fare_quartile >= 3 THEN 'High Potential (Low demand, High fare)'
        WHEN demand_quartile <= 2 AND fare_quartile <= 2 THEN 'Low Priority (Low demand, Low fare)'
        WHEN demand_quartile >= 3 AND fare_quartile >= 3 THEN 'Premium Zone (High demand, High fare)'
        ELSE 'Saturated (High demand, Low fare)'
    END as zone_category
FROM zone_ranking zr
JOIN dim_zones z ON zr.pickup_location_id = z.location_id
ORDER BY 
    CASE 
        WHEN demand_quartile <= 2 AND fare_quartile >= 3 THEN 1
        ELSE 2
    END,
    avg_fare DESC;

SELECT *
FROM vw_q12_underserved_zones;
-- Identifies zones with high fares but low demand (expansion opportunities)


-------------------------------------------------------------------------
-- Q13: Platform Market Share (Uber vs Lyft)
CREATE OR REPLACE VIEW vw_q13_platform_market_share AS
SELECT 
    TO_CHAR(DATE_TRUNC('month', pickup_datetime), 'YYYY-MM') as month,
    service_name,
    COUNT(*) as total_trips,
    SUM(total_revenue) as monthly_revenue,
    ROUND(AVG(base_passenger_fare)::numeric, 2) as avg_fare
FROM v_clean_rides
GROUP BY 1, 2
ORDER BY 1, 3 DESC;

SELECT *
FROM vw_q13_platform_market_share;


-- Q14: High-Value Trip Retention (Premium vs Standard)
-- Checks how many "Big Ticket" rides ($50+) happen in Jan vs June
CREATE OR REPLACE VIEW vw_q14_premium_trip_retention AS
WITH jan_high_value AS (
    SELECT COUNT(*) as jan_count
    FROM v_clean_rides
    WHERE DATE_TRUNC('month', pickup_datetime) = '2025-01-01'
    AND total_revenue >= 50
),
june_high_value AS (
    SELECT COUNT(*) as june_count
    FROM v_clean_rides
    WHERE DATE_TRUNC('month', pickup_datetime) = '2025-06-01'
    AND total_revenue >= 50
)
SELECT 
    jan_count as high_value_trips_jan,
    june_count as high_value_trips_june,
    ROUND(((june_count::numeric - jan_count) / NULLIF(jan_count, 0) * 100), 2) as growth_pct
FROM jan_high_value, june_high_value;

SELECT *
FROM vw_q14_premium_trip_retention;


-- Q15: Service Efficiency (Revenue per Minute/Mile)
CREATE OR REPLACE VIEW vw_q15_service_efficiency AS
SELECT 
    service_name,
    ROUND((SUM(total_revenue) / NULLIF(SUM(trip_miles), 0))::numeric, 2) as rev_per_mile,
    ROUND((SUM(total_revenue) / NULLIF(SUM(trip_time / 60.0), 0))::numeric, 2) as rev_per_minute,
    ROUND((AVG(tips / NULLIF(base_passenger_fare, 0)) * 100)::numeric, 2) as avg_tip_percentage
FROM v_clean_rides
GROUP BY service_name;

SELECT *
FROM vw_q15_service_efficiency;


-- ============================================================================
-- SECTION 2: DIMENSION TABLES (For Power BI Star Schema)
-- These are reference tables that won't change
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DIM: Date Dimension
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_date AS
SELECT 
    date_value::DATE as date,
    EXTRACT(YEAR FROM date_value) as year,
    EXTRACT(MONTH FROM date_value) as month,
    EXTRACT(DAY FROM date_value) as day,
    EXTRACT(DOW FROM date_value) as day_of_week,
    TO_CHAR(date_value, 'Day') as day_name,
    TO_CHAR(date_value, 'Month') as month_name,
    EXTRACT(QUARTER FROM date_value) as quarter,
    EXTRACT(WEEK FROM date_value) as week_of_year,
    CASE 
        WHEN EXTRACT(DOW FROM date_value) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END as day_type
FROM generate_series('2025-01-01'::date, '2025-12-31'::date, '1 day') as date_value;
-- Date lookup table for time-based analysis


-- ----------------------------------------------------------------------------
-- DIM: Service Provider Dimension
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_services AS
SELECT 'HV0003' as license_num, 'Uber' as service_name, 'Black' as service_color
UNION ALL
SELECT 'HV0005', 'Lyft', 'Pink';
-- Service provider reference



-- ============================================================================
-- SECTION 3: FACT TABLE
-- ============================================================================

CREATE OR REPLACE VIEW vw_rides_fact AS
SELECT 
    DATE(pickup_datetime) as ride_date,
    pickup_location_id,
    dropoff_location_id,
    service_name,
    dispatching_base_num as driver_id,
    
    -- Aggregated metrics
    COUNT(*) as total_trips,
    SUM(total_revenue) as total_revenue,
    SUM(base_passenger_fare) as total_base_fare,
    SUM(tips) as total_tips,
    SUM(tolls) as total_tolls,
    SUM(congestion_surcharge) as total_congestion,
    SUM(airport_fee) as total_airport_fees,
    SUM(trip_miles) as total_miles,
    SUM(trip_time) as total_trip_seconds,
    
    -- Averages
    ROUND(AVG(base_passenger_fare)::numeric, 2) as avg_fare,
    ROUND(AVG(trip_miles)::numeric, 2) as avg_distance,
    ROUND(AVG(trip_duration_minutes)::numeric, 2) as avg_duration_minutes,
    
    -- Counts by type
    SUM(CASE WHEN shared_request_flag = 'Y' THEN 1 ELSE 0 END) as shared_requested,
    SUM(CASE WHEN shared_match_flag = 'Y' THEN 1 ELSE 0 END) as shared_matched,
    SUM(CASE WHEN wav_request_flag = 'Y' THEN 1 ELSE 0 END) as wav_requested
    
FROM v_clean_rides
GROUP BY 
    DATE(pickup_datetime),
    pickup_location_id,
    dropoff_location_id,
    service_name,
    dispatching_base_num;



-- ============================================================================
-- SECTION 4: DASHBOARD-SPECIFIC VIEWS
-- Pre-aggregated views optimized for each dashboard
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DASHBOARD 1: Executive Overview
-- ----------------------------------------------------------------------------

-- Revenue trend by service (for line chart)
CREATE OR REPLACE VIEW vw_exec_revenue_trend AS
SELECT 
    DATE(pickup_datetime) as date,
    service_name,
    SUM(total_revenue) as revenue,
    COUNT(*) as trips
FROM v_clean_rides
GROUP BY DATE(pickup_datetime), service_name
ORDER BY date, service_name;


-- Monthly summary (for clustered column chart)
CREATE OR REPLACE VIEW vw_exec_monthly_summary AS
SELECT 
    TO_CHAR(DATE_TRUNC('month', pickup_datetime), 'YYYY-MM') as month,
    service_name,
    COUNT(*) as total_trips,
    SUM(total_revenue) as total_revenue,
    AVG(base_passenger_fare) as avg_fare
FROM v_clean_rides
GROUP BY DATE_TRUNC('month', pickup_datetime), service_name
ORDER BY month, service_name;


-- Top 5 pickup zones (for bar chart)

CREATE VIEW vw_exec_top_zones AS
SELECT 
    z.zone as pickup_neighborhood,
    z.borough,
    COUNT(*) as trips,
    SUM(r.total_revenue) as revenue
FROM v_clean_rides r
JOIN dim_zones z ON r.pickup_location_id = z.location_id
GROUP BY z.zone, z.borough
ORDER BY revenue DESC
LIMIT 5;


-- ----------------------------------------------------------------------------
-- DASHBOARD 2: Operational Performance
-- ----------------------------------------------------------------------------

-- Demand heatmap data
CREATE OR REPLACE VIEW vw_ops_demand_heatmap AS
SELECT 
    EXTRACT(DOW FROM pickup_datetime) as day_of_week,
    EXTRACT(HOUR FROM pickup_datetime) as hour,
    COUNT(*) as trip_count
FROM v_clean_rides
GROUP BY 
    EXTRACT(DOW FROM pickup_datetime),
    EXTRACT(HOUR FROM pickup_datetime)
ORDER BY day_of_week, hour;


-- Trip distance distribution
CREATE OR REPLACE VIEW vw_ops_distance_distribution AS
SELECT distance_range, trip_count
FROM (
    SELECT 
        CASE 
            WHEN trip_miles < 1 THEN 'Under 1 mile'
            WHEN trip_miles BETWEEN 1 AND 3 THEN '1-3 miles'
            WHEN trip_miles BETWEEN 3 AND 5 THEN '3-5 miles'
            WHEN trip_miles BETWEEN 5 AND 10 THEN '5-10 miles'
            WHEN trip_miles BETWEEN 10 AND 20 THEN '10-20 miles'
            ELSE 'Over 20 miles'
        END as distance_range,
        COUNT(*) as trip_count
    FROM v_clean_rides
    GROUP BY 1
) sub
ORDER BY 
    CASE distance_range
        WHEN 'Under 1 mile' THEN 1
        WHEN '1-3 miles' THEN 2
        WHEN '3-5 miles' THEN 3
        WHEN '5-10 miles' THEN 4
        WHEN '10-20 miles' THEN 5
        ELSE 6
    END;

-- Fare vs distance (for scatter plot)
CREATE OR REPLACE VIEW vw_ops_fare_by_distance AS
SELECT 
    ROUND(trip_miles::numeric, 1) as distance_miles,
    ROUND(AVG(base_passenger_fare)::numeric, 2) as avg_fare,
    COUNT(*) as trip_count
FROM v_clean_rides
WHERE trip_miles BETWEEN 0.1 AND 50
GROUP BY ROUND(trip_miles::numeric, 1)
HAVING COUNT(*) > 100
ORDER BY distance_miles;


-- ----------------------------------------------------------------------------
-- DASHBOARD 3: Zone & Market Analysis
-- ----------------------------------------------------------------------------


-- 2. Zone revenue for map
CREATE VIEW vw_zone_revenue_map AS
SELECT 
    z.location_id as zone_id,
    z.zone as zone_name,
    z.borough,
    COUNT(*) as total_trips,
    SUM(r.total_revenue) as total_revenue,
    AVG(r.base_passenger_fare) as avg_fare
FROM v_clean_rides r
JOIN dim_zones z ON r.pickup_location_id = z.location_id
GROUP BY z.location_id, z.zone, z.borough;

-- 3. Top 10 and Bottom 10 zones
CREATE VIEW vw_zone_top_bottom AS
(
    SELECT 
        z.zone as zone_name,
        SUM(r.total_revenue) as revenue,
        'Top 10' as category
    FROM v_clean_rides r
    JOIN dim_zones z ON r.pickup_location_id = z.location_id
    GROUP BY z.zone
    ORDER BY revenue DESC
    LIMIT 10
)
UNION ALL
(
    SELECT 
        z.zone as zone_name,
        SUM(r.total_revenue) as revenue,
        'Bottom 10' as category
    FROM v_clean_rides r
    JOIN dim_zones z ON r.pickup_location_id = z.location_id
    GROUP BY z.zone
    ORDER BY revenue ASC
    LIMIT 10
);

-- ============================================================================
-- VERIFICATION QUERIES
-- Run these to verify all views were created successfully
-- ============================================================================

-- Count all views created
SELECT 
    schemaname,
    viewname
FROM pg_views
WHERE viewname LIKE 'vw_%' OR viewname LIKE 'dim_%' OR viewname LIKE 'v_clean%'
ORDER BY viewname;


-- Test each business question view
SELECT 'Q1: Total Revenue' as question, COUNT(*) as row_count FROM vw_q1_total_revenue
UNION ALL SELECT 'Q2: Monthly Growth', COUNT(*) FROM vw_q2_monthly_growth
UNION ALL SELECT 'Q3: Service Revenue', COUNT(*) FROM vw_q3_service_revenue
UNION ALL SELECT 'Q4: Revenue Trend', COUNT(*) FROM vw_q4_revenue_trend
UNION ALL SELECT 'Q5: Trip Metrics', COUNT(*) FROM vw_q5_trip_metrics
UNION ALL SELECT 'Q6: Demand Patterns', COUNT(*) FROM vw_q6_demand_patterns
UNION ALL SELECT 'Q7: Driver Activity', COUNT(*) FROM vw_q7_driver_activity
UNION ALL SELECT 'Q8: Fare Per Mile', COUNT(*) FROM vw_q8_fare_per_mile
UNION ALL SELECT 'Q9: Top Pickup Zones', COUNT(*) FROM vw_q9_top_pickup_zones
UNION ALL SELECT 'Q10: Zone Growth', COUNT(*) FROM vw_q10_zone_growth
UNION ALL SELECT 'Q11: Top Routes', COUNT(*) FROM vw_q11_top_routes
UNION ALL SELECT 'Q12: Underserved Zones', COUNT(*) FROM vw_q12_underserved_zones
UNION ALL SELECT 'Q13: Monthly Drivers', COUNT(*) FROM vw_q13_monthly_driver_count
UNION ALL SELECT 'Q14: Driver Retention', COUNT(*) FROM vw_q14_driver_retention
UNION ALL SELECT 'Q15: Revenue Per Driver', COUNT(*) FROM vw_q15_revenue_per_driver;
