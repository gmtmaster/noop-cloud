SELECT 'cloud_device' AS table_name, count(*) FROM cloud_device
UNION ALL SELECT 'cloud_sync_batch', count(*) FROM cloud_sync_batch
UNION ALL SELECT 'cloud_daily_metric', count(*) FROM cloud_daily_metric
UNION ALL SELECT 'cloud_sleep_session', count(*) FROM cloud_sleep_session
UNION ALL SELECT 'cloud_workout', count(*) FROM cloud_workout
UNION ALL SELECT 'cloud_metric_series', count(*) FROM cloud_metric_series
ORDER BY table_name;

SELECT source_device_id, count(*) AS daily_metrics
FROM cloud_daily_metric
GROUP BY source_device_id
ORDER BY source_device_id;

SELECT source_device_id, count(*) AS sleep_sessions
FROM cloud_sleep_session
GROUP BY source_device_id
ORDER BY source_device_id;

SELECT source_device_id, count(*) AS workouts
FROM cloud_workout
GROUP BY source_device_id
ORDER BY source_device_id;

SELECT source_device_id, key, count(*) AS metric_series
FROM cloud_metric_series
GROUP BY source_device_id, key
ORDER BY source_device_id, key;

SELECT client_batch_id, count(*) AS batches
FROM cloud_sync_batch
GROUP BY client_batch_id
ORDER BY client_batch_id;

SELECT 'cloud_daily_metric' AS table_name, count(*) AS duplicate_natural_keys
FROM (
    SELECT cloud_device_id, source_device_id, day
    FROM cloud_daily_metric
    GROUP BY cloud_device_id, source_device_id, day
    HAVING count(*) > 1
) duplicates
UNION ALL
SELECT 'cloud_sleep_session', count(*)
FROM (
    SELECT cloud_device_id, source_device_id, start_ts
    FROM cloud_sleep_session
    GROUP BY cloud_device_id, source_device_id, start_ts
    HAVING count(*) > 1
) duplicates
UNION ALL
SELECT 'cloud_workout', count(*)
FROM (
    SELECT cloud_device_id, source_device_id, start_ts, sport
    FROM cloud_workout
    GROUP BY cloud_device_id, source_device_id, start_ts, sport
    HAVING count(*) > 1
) duplicates
UNION ALL
SELECT 'cloud_metric_series', count(*)
FROM (
    SELECT cloud_device_id, source_device_id, day, key
    FROM cloud_metric_series
    GROUP BY cloud_device_id, source_device_id, day, key
    HAVING count(*) > 1
) duplicates
ORDER BY table_name;
