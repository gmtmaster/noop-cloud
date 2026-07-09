ALTER TABLE cloud_user
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

CREATE INDEX IF NOT EXISTS idx_cloud_auth_session_user ON cloud_auth_session(cloud_user_id);
CREATE INDEX IF NOT EXISTS idx_cloud_auth_session_device ON cloud_auth_session(cloud_device_id);
