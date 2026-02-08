# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_08_171402) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "note_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "note_id", null: false
    t.integer "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["note_id", "tag_id"], name: "index_note_tags_on_note_id_and_tag_id", unique: true
    t.index ["note_id"], name: "index_note_tags_on_note_id"
    t.index ["tag_id"], name: "index_note_tags_on_tag_id"
  end

  create_table "note_versions", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.text "metadata"
    t.integer "note_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["note_id", "version_number"], name: "index_note_versions_on_note_id_and_version_number", unique: true
    t.index ["note_id"], name: "index_note_versions_on_note_id"
  end

  create_table "notes", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "max_size", default: 32768, null: false
    t.boolean "pinned", default: false, null: false
    t.string "title"
    t.boolean "trashed", default: false, null: false
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "archived"], name: "index_notes_on_user_id_and_archived"
    t.index ["user_id", "pinned"], name: "index_notes_on_user_id_and_pinned"
    t.index ["user_id", "trashed"], name: "index_notes_on_user_id_and_trashed"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "note_id", null: false
    t.integer "permission", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["note_id", "user_id"], name: "index_shares_on_note_id_and_user_id", unique: true
    t.index ["note_id"], name: "index_shares_on_note_id"
    t.index ["user_id"], name: "index_shares_on_user_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "color", default: "#6b7280"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "name"], name: "index_tags_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "api_token"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.text "preferences"
    t.string "provider", default: "google_oauth2", null: false
    t.string "refresh_token"
    t.integer "role", default: 0, null: false
    t.integer "session_timeout", default: 3600, null: false
    t.datetime "token_expires_at"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["uid"], name: "index_users_on_uid", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "note_tags", "notes"
  add_foreign_key "note_tags", "tags"
  add_foreign_key "note_versions", "notes"
  add_foreign_key "notes", "users"
  add_foreign_key "shares", "notes"
  add_foreign_key "shares", "users"
  add_foreign_key "tags", "users"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
