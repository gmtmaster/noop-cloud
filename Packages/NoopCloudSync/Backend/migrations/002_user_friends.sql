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
