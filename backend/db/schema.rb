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

ActiveRecord::Schema[8.1].define(version: 2026_05_28_032718) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "bank_connection_id"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "BRL", null: false
    t.string "external_id"
    t.string "institution", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.uuid "owner_membership_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["bank_connection_id", "external_id"], name: "index_accounts_on_connection_and_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["bank_connection_id"], name: "index_accounts_on_bank_connection_id"
    t.index ["owner_membership_id"], name: "index_accounts_on_owner_membership_id"
    t.index ["workspace_id"], name: "index_accounts_on_workspace_id"
    t.check_constraint "institution::text = ANY (ARRAY['nubank'::character varying, 'inter'::character varying, 'itau'::character varying, 'santander'::character varying, 'bb'::character varying, 'manual'::character varying]::text[])", name: "accounts_institution_check"
    t.check_constraint "kind::text = ANY (ARRAY['checking'::character varying, 'credit_card'::character varying]::text[])", name: "accounts_kind_check"
  end

  create_table "bank_connections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "credentials_ref"
    t.text "error_message"
    t.string "external_connection_id", null: false
    t.datetime "last_sync_at"
    t.uuid "owner_membership_id", null: false
    t.string "provider", default: "pluggy", null: false
    t.string "status", default: "connected", null: false
    t.date "sync_history_since", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["owner_membership_id"], name: "index_bank_connections_on_owner_membership_id"
    t.index ["provider", "external_connection_id"], name: "index_bank_connections_on_provider_and_external_connection_id", unique: true
    t.index ["workspace_id"], name: "index_bank_connections_on_workspace_id"
    t.check_constraint "provider::text = ANY (ARRAY['pluggy'::character varying, 'manual'::character varying]::text[])", name: "bank_connections_provider_check"
    t.check_constraint "status::text = ANY (ARRAY['connected'::character varying, 'syncing'::character varying, 'expired'::character varying, 'error'::character varying, 'disconnected'::character varying]::text[])", name: "bank_connections_status_check"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "google_uid", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true
  end

  create_table "workspace_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "joined_at", null: false
    t.string "role", default: "editor", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["user_id", "workspace_id"], name: "index_workspace_memberships_on_user_id_and_workspace_id", unique: true
    t.index ["user_id"], name: "index_workspace_memberships_on_user_id"
    t.index ["workspace_id"], name: "index_workspace_memberships_on_workspace_id"
    t.check_constraint "role::text = ANY (ARRAY['editor'::character varying, 'viewer'::character varying]::text[])", name: "workspace_memberships_role_check"
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_user_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_workspaces_on_created_by_user_id"
  end

  add_foreign_key "accounts", "bank_connections"
  add_foreign_key "accounts", "workspace_memberships", column: "owner_membership_id"
  add_foreign_key "accounts", "workspaces"
  add_foreign_key "bank_connections", "workspace_memberships", column: "owner_membership_id"
  add_foreign_key "bank_connections", "workspaces"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
  add_foreign_key "workspaces", "users", column: "created_by_user_id"
end
