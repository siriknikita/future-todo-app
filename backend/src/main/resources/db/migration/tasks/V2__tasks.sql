CREATE SCHEMA tasks;

CREATE TABLE tasks.list_groups (
    id         uuid PRIMARY KEY,
    owner_id   uuid             NOT NULL,
    name       text             NOT NULL DEFAULT '',
    position   double precision NOT NULL DEFAULT 0,
    deleted    boolean          NOT NULL DEFAULT false,
    clocks     text             NOT NULL DEFAULT '{}',
    created_at timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX list_groups_owner_idx ON tasks.list_groups (owner_id);

CREATE TABLE tasks.lists (
    id         uuid PRIMARY KEY,
    owner_id   uuid             NOT NULL,
    group_id   uuid,
    name       text             NOT NULL DEFAULT '',
    icon       text,
    theme      text,
    position   double precision NOT NULL DEFAULT 0,
    deleted    boolean          NOT NULL DEFAULT false,
    clocks     text             NOT NULL DEFAULT '{}',
    created_at timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX lists_owner_idx ON tasks.lists (owner_id);

CREATE TABLE tasks.tasks (
    id              uuid PRIMARY KEY,
    list_id         uuid             NOT NULL REFERENCES tasks.lists (id) ON DELETE CASCADE,
    title           varchar(255)     NOT NULL DEFAULT '',
    note            text             NOT NULL DEFAULT '',
    completed       boolean          NOT NULL DEFAULT false,
    completed_at    timestamptz,
    important       boolean          NOT NULL DEFAULT false,
    due_date        date,
    reminder_at     timestamptz,
    repeat_type     text,
    repeat_interval integer          NOT NULL DEFAULT 1,
    repeat_days     text,
    my_day_date     date,
    assignee_id     uuid,
    position        double precision NOT NULL DEFAULT 0,
    deleted         boolean          NOT NULL DEFAULT false,
    clocks          text             NOT NULL DEFAULT '{}',
    created_at      timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX tasks_list_idx ON tasks.tasks (list_id);
CREATE INDEX tasks_assignee_idx ON tasks.tasks (assignee_id);
CREATE INDEX tasks_fts_idx ON tasks.tasks USING gin (to_tsvector('simple', title || ' ' || note));

CREATE TABLE tasks.steps (
    id         uuid PRIMARY KEY,
    task_id    uuid             NOT NULL REFERENCES tasks.tasks (id) ON DELETE CASCADE,
    title      text             NOT NULL DEFAULT '',
    completed  boolean          NOT NULL DEFAULT false,
    position   double precision NOT NULL DEFAULT 0,
    deleted    boolean          NOT NULL DEFAULT false,
    clocks     text             NOT NULL DEFAULT '{}',
    created_at timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX steps_task_idx ON tasks.steps (task_id);
