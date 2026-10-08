CREATE SCHEMA accounts;

CREATE TABLE accounts.users (
    id             uuid PRIMARY KEY,
    email          text        NOT NULL UNIQUE,
    password_hash  text,
    display_name   text        NOT NULL,
    photo_url      text,
    email_verified boolean     NOT NULL DEFAULT false,
    role           text        NOT NULL DEFAULT 'USER',
    blocked        boolean     NOT NULL DEFAULT false,
    oauth_provider text,
    oauth_subject  text,
    settings       text        NOT NULL DEFAULT '{}',
    created_at     timestamptz NOT NULL DEFAULT now(),
    last_seen_at   timestamptz
);

CREATE UNIQUE INDEX users_oauth_idx ON accounts.users (oauth_provider, oauth_subject) WHERE oauth_provider IS NOT NULL;

CREATE TABLE accounts.email_tokens (
    token      text PRIMARY KEY,
    user_id    uuid        NOT NULL REFERENCES accounts.users (id) ON DELETE CASCADE,
    kind       text        NOT NULL,
    expires_at timestamptz NOT NULL,
    used       boolean     NOT NULL DEFAULT false
);

CREATE TABLE accounts.sessions (
    id           uuid PRIMARY KEY,
    user_id      uuid        NOT NULL REFERENCES accounts.users (id) ON DELETE CASCADE,
    token_hash   text        NOT NULL UNIQUE,
    device_name  text,
    platform     text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL
);

CREATE INDEX sessions_user_idx ON accounts.sessions (user_id);
