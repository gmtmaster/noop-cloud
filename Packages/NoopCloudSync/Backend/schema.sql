CREATE TABLE IF NOT EXISTS cloud_user (
    id UUID PRIMARY KEY,
    username TEXT UNIQUE,
    display_name TEXT,
    avatar_url TEXT,
    share_recovery BOOLEAN NOT NULL DEFAULT true,
    share_sleep BOOLEAN NOT NULL DEFAULT true,
    share_workouts BOOLEAN NOT NULL DEFAULT true,
    share_daily_effort BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cloud_device (
    id UUID PRIMARY KEY,
    cloud_user_id UUID NULL REFERENCES cloud_user(id),
    device_token_hash TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ
);

ALTER TABLE cloud_device
    ADD COLUMN IF NOT EXISTS cloud_user_id UUID NULL REFERENCES cloud_user(id);

ALTER TABLE cloud_user
    ADD COLUMN IF NOT EXISTS share_recovery BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS share_sleep BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS share_workouts BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS share_daily_effort BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS password_hash TEXT,
    ADD COLUMN IF NOT EXISTS password_salt TEXT;

CREATE TABLE IF NOT EXISTS cloud_auth_session (
    id UUID PRIMARY KEY,
    cloud_user_id UUID NOT NULL REFERENCES cloud_user(id),
    cloud_device_id UUID NULL REFERENCES cloud_device(id),
    session_token_hash TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cloud_friendship (
    id UUID PRIMARY KEY,
    requester_user_id UUID NOT NULL REFERENCES cloud_user(id),
    addressee_user_id UUID NOT NULL REFERENCES cloud_user(id),
    status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'blocked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (requester_user_id <> addressee_user_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS cloud_friendship_pair_unique
    ON cloud_friendship (
        LEAST(requester_user_id, addressee_user_id),
        GREATEST(requester_user_id, addressee_user_id)
    );

CREATE TABLE IF NOT EXISTS cloud_sync_batch (
    cloud_device_id UUID NOT NULL REFERENCES cloud_device(id),
    client_batch_id TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    app_version TEXT,
    source_device_ids TEXT[] NOT NULL DEFAULT '{}',
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (cloud_device_id, client_batch_id)
);

CREATE TABLE IF NOT EXISTS cloud_daily_metric (
    cloud_device_id UUID NOT NULL REFERENCES cloud_device(id),
    source_device_id TEXT NOT NULL,
    day DATE NOT NULL,
    payload JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (cloud_device_id, source_device_id, day)
);

CREATE TABLE IF NOT EXISTS cloud_sleep_session (
    cloud_device_id UUID NOT NULL REFERENCES cloud_device(id),
    source_device_id TEXT NOT NULL,
    start_ts BIGINT NOT NULL,
    payload JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (cloud_device_id, source_device_id, start_ts)
);

CREATE TABLE IF NOT EXISTS cloud_workout (
    cloud_device_id UUID NOT NULL REFERENCES cloud_device(id),
    source_device_id TEXT NOT NULL,
    start_ts BIGINT NOT NULL,
    sport TEXT NOT NULL,
    payload JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (cloud_device_id, source_device_id, start_ts, sport)
);

CREATE TABLE IF NOT EXISTS cloud_metric_series (
    cloud_device_id UUID NOT NULL REFERENCES cloud_device(id),
    source_device_id TEXT NOT NULL,
    day DATE NOT NULL,
    key TEXT NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (cloud_device_id, source_device_id, day, key)
);
