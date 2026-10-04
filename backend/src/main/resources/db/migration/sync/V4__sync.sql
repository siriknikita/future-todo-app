CREATE SCHEMA sync;

CREATE TABLE sync.changes (
    seq         bigserial PRIMARY KEY,
    entity_type text        NOT NULL,
    entity_id   uuid        NOT NULL,
    list_id     uuid,
    actor_id    uuid        NOT NULL,
    deleted     boolean     NOT NULL DEFAULT false,
    payload     text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX changes_list_idx ON sync.changes (list_id, seq);
CREATE INDEX changes_actor_idx ON sync.changes (actor_id, seq);
CREATE INDEX changes_entity_idx ON sync.changes (entity_type, entity_id, seq);
