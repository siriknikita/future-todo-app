CREATE SCHEMA notifications;

CREATE TABLE notifications.notifications (
    id         uuid PRIMARY KEY,
    user_id    uuid        NOT NULL,
    type       text        NOT NULL,
    title      text        NOT NULL,
    body       text        NOT NULL DEFAULT '',
    data       text        NOT NULL DEFAULT '{}',
    read       boolean     NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_user_idx ON notifications.notifications (user_id, created_at DESC);

CREATE TABLE notifications.preferences (
    user_id      uuid PRIMARY KEY,
    assignment   boolean NOT NULL DEFAULT true,
    reminders    boolean NOT NULL DEFAULT true,
    email_digest boolean NOT NULL DEFAULT false
);
