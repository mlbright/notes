CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "active_storage_blobs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "filename" varchar NOT NULL, "content_type" varchar, "metadata" text, "service_name" varchar NOT NULL, "byte_size" bigint NOT NULL, "checksum" varchar, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_active_storage_blobs_on_key" ON "active_storage_blobs" ("key") /*application='Web'*/;
CREATE TABLE IF NOT EXISTS "active_storage_attachments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "record_type" varchar NOT NULL, "record_id" bigint NOT NULL, "blob_id" bigint NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c3b3935057"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE INDEX "index_active_storage_attachments_on_blob_id" ON "active_storage_attachments" ("blob_id") /*application='Web'*/;
CREATE UNIQUE INDEX "index_active_storage_attachments_uniqueness" ON "active_storage_attachments" ("record_type", "record_id", "name", "blob_id") /*application='Web'*/;
CREATE TABLE IF NOT EXISTS "active_storage_variant_records" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "blob_id" bigint NOT NULL, "variation_digest" varchar NOT NULL, CONSTRAINT "fk_rails_993965df05"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE UNIQUE INDEX "index_active_storage_variant_records_uniqueness" ON "active_storage_variant_records" ("blob_id", "variation_digest") /*application='Web'*/;
CREATE TABLE IF NOT EXISTS "notes" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "title" varchar, "body" text, "pinned" boolean DEFAULT FALSE NOT NULL, "archived" boolean DEFAULT FALSE NOT NULL, "trashed" boolean DEFAULT FALSE NOT NULL, "trashed_at" datetime(6), "max_size" integer DEFAULT 32768 NOT NULL, "user_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_7f2323ad43"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
);
CREATE INDEX "index_notes_on_user_id" ON "notes" ("user_id") /*application='Web'*/;
CREATE INDEX "index_notes_on_user_id_and_pinned" ON "notes" ("user_id", "pinned") /*application='Web'*/;
CREATE INDEX "index_notes_on_user_id_and_archived" ON "notes" ("user_id", "archived") /*application='Web'*/;
CREATE INDEX "index_notes_on_user_id_and_trashed" ON "notes" ("user_id", "trashed") /*application='Web'*/;
CREATE TABLE IF NOT EXISTS "tags" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "color" varchar DEFAULT '#6b7280', "user_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_e689f6d0cc"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
);
CREATE INDEX "index_tags_on_user_id" ON "tags" ("user_id") /*application='Web'*/;
CREATE UNIQUE INDEX "index_tags_on_user_id_and_name" ON "tags" ("user_id", "name") /*application='Web'*/;
CREATE TABLE IF NOT EXISTS "note_tags" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "note_id" integer NOT NULL, "tag_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_881102a791"
FOREIGN KEY ("note_id")
  REFERENCES "notes" ("id")
, CONSTRAINT "fk_rails_7e32f68bcb"
FOREIGN KEY ("tag_id")
  REFERENCES "tags" ("id")
);
CREATE INDEX "index_note_tags_on_note_id" ON "note_tags" ("note_id") /*application='Web'*/;
CREATE INDEX "index_note_tags_on_tag_id" ON "note_tags" ("tag_id") /*application='Web'*/;
CREATE UNIQUE INDEX "index_note_tags_on_note_id_and_tag_id" ON "note_tags" ("note_id", "tag_id") /*application='Web'*/;
CREATE TABLE IF NOT EXISTS "note_versions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "note_id" integer NOT NULL, "title" varchar, "body" text, "version_number" integer NOT NULL, "metadata" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_611f87a5ae"
FOREIGN KEY ("note_id")
  REFERENCES "notes" ("id")
);
CREATE INDEX "index_note_versions_on_note_id" ON "note_versions" ("note_id") /*application='Web'*/;
CREATE UNIQUE INDEX "index_note_versions_on_note_id_and_version_number" ON "note_versions" ("note_id", "version_number") /*application='Web'*/;
CREATE TABLE IF NOT EXISTS "shares" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "note_id" integer NOT NULL, "user_id" integer NOT NULL, "permission" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_ce017fb657"
FOREIGN KEY ("note_id")
  REFERENCES "notes" ("id")
, CONSTRAINT "fk_rails_d671d25093"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
);
CREATE INDEX "index_shares_on_note_id" ON "shares" ("note_id") /*application='Web'*/;
CREATE INDEX "index_shares_on_user_id" ON "shares" ("user_id") /*application='Web'*/;
CREATE UNIQUE INDEX "index_shares_on_note_id_and_user_id" ON "shares" ("note_id", "user_id") /*application='Web'*/;
CREATE VIRTUAL TABLE notes_search_index USING fts5(
        title,
        body,
        content='notes',
        content_rowid='id',
        tokenize='porter'
      )
/* notes_search_index(title,body) */;
CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
        INSERT INTO notes_search_index(rowid, title, body) VALUES (new.id, new.title, new.body);
      END;
CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
        INSERT INTO notes_search_index(notes_search_index, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
      END;
CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
        INSERT INTO notes_search_index(notes_search_index, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
        INSERT INTO notes_search_index(rowid, title, body) VALUES (new.id, new.title, new.body);
      END;
CREATE TABLE IF NOT EXISTS "users" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "email" varchar NOT NULL, "role" integer DEFAULT 0 NOT NULL, "session_timeout" integer DEFAULT 3600 NOT NULL, "preferences" text, "uid" varchar, "provider" varchar DEFAULT NULL, "api_token" varchar, "refresh_token" varchar, "token_expires_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "password_digest" varchar);
CREATE UNIQUE INDEX "index_users_on_email" ON "users" ("email");
CREATE UNIQUE INDEX "index_users_on_uid" ON "users" ("uid");
CREATE UNIQUE INDEX "index_users_on_api_token" ON "users" ("api_token");
INSERT INTO "schema_migrations" (version) VALUES
('20260208174535'),
('20260208171402'),
('20260208170506'),
('20260208170502'),
('20260208170458'),
('20260208170454'),
('20260208170449'),
('20260208170445'),
('20260208170432');

