
-- 💰 THE MONEY (Financials)
SELECT 'Q1: Overall Revenue' as insight;
SELECT *
FROM vw_q1_total_revenue;
SELECT 'Q2: Growth Trends' as insight;
SELECT *
FROM vw_q2_monthly_growth;
SELECT 'Q3: Uber vs Lyft Share' as insight;
SELECT *
FROM vw_q3_service_revenue;
SELECT 'Q4: Daily Income' as insight;
SELECT *
FROM vw_q4_revenue_trend;
-- ⏱️ PILLAR 2: THE TRIP (Efficiency)
SELECT 'Q5: Avg Miles & Minutes' as insight;
SELECT *
FROM vw_q5_trip_metrics;
SELECT 'Q6: Peak Demand Times' as insight;
SELECT *
FROM vw_q6_demand_patterns;
SELECT 'Q7: Driver Activity' as insight;
SELECT *
FROM vw_q7_driver_activity;
SELECT 'Q8: Profit Per Mile' as insight;
SELECT *
FROM vw_q8_fare_per_mile;
-- 📍 PILLAR 3: THE MAP (Geography)
SELECT 'Q9: Busiest Neighborhoods' as insight;
SELECT *
FROM vw_q9_top_pickup_zones;
SELECT 'Q10: Trending Zones' as insight;
SELECT *
FROM vw_q10_zone_growth;
SELECT 'Q11: Top A-to-B Routes' as insight;
SELECT *
FROM vw_q11_top_routes;
SELECT 'Q12: Underserved Hotspots' as insight;
SELECT *
FROM vw_q12_underserved_zones;
-- 🚖 PILLAR 4: THE DRIVERS (Workforce)
SELECT 'Q13: Fleet Size' as insight;
SELECT *
FROM vw_q13_monthly_driver_count;
SELECT 'Q14: Driver Loyalty' as insight;
SELECT *
FROM vw_q14_driver_retention;
SELECT 'Q15: Earnings per Driver' as insight;
SELECT *
FROM vw_q15_revenue_per_driver;
/* ✅ MISSION COMPLETE: 120 Million rows analyzed. 
 Ready for Power BI visualization! 
 */