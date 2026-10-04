CREATE SCHEMA sharing;

CREATE TABLE sharing.list_members (
    list_id   uuid        NOT NULL,
    user_id   uuid        NOT NULL,
    role      text        NOT NULL,
    joined_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (list_id, user_id)
);

CREATE INDEX list_members_user_idx ON sharing.list_members (user_id);

CREATE TABLE sharing.invitations (
    token      text PRIMARY KEY,
    list_id    uuid        NOT NULL,
    created_by uuid        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked    boolean     NOT NULL DEFAULT false
);

CREATE INDEX invitations_list_idx ON sharing.invitations (list_id);
