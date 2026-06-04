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

ActiveRecord::Schema[8.1].define(version: 2026_06_04_150000) do
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
    t.check_constraint "institution::text = ANY (ARRAY['nubank'::character varying, 'inter'::character varying, 'itau'::character varying, 'santander'::character varying, 'bb'::character varying, 'sandbox'::character varying, 'manual'::character varying]::text[])", name: "accounts_institution_check"
    t.check_constraint "kind::text = ANY (ARRAY['checking'::character varying, 'credit_card'::character varying]::text[])", name: "accounts_kind_check"
  end

  create_table "ai_learned_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "descriptor_pattern", null: false
    t.text "improved_title"
    t.datetime "last_seen_at", null: false
    t.integer "match_count", default: 1, null: false
    t.uuid "tag_ids", default: [], array: true
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "descriptor_pattern"], name: "index_ai_learned_rules_on_workspace_and_pattern", unique: true
    t.index ["workspace_id"], name: "index_ai_learned_rules_on_workspace_id"
  end

  create_table "bank_connection_syncs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "bank_connection_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_count", default: 0, null: false
    t.integer "duplicate_count", default: 0, null: false
    t.integer "duration_seconds"
    t.integer "error_count", default: 0, null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "started_at", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["bank_connection_id", "started_at"], name: "idx_on_bank_connection_id_started_at_de63f7aa5b"
    t.index ["bank_connection_id"], name: "index_bank_connection_syncs_on_bank_connection_id"
  end

  create_table "bank_connections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "credentials_ref"
    t.text "error_message"
    t.string "external_connection_id", null: false
    t.datetime "last_sync_at"
    t.integer "last_sync_created_count", default: 0, null: false
    t.integer "last_sync_duplicate_count", default: 0, null: false
    t.integer "last_sync_duration_seconds"
    t.integer "last_sync_error_count", default: 0, null: false
    t.datetime "next_sync_at"
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

  create_table "categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "icon"
    t.citext "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "name"], name: "index_categories_on_workspace_id_and_name", unique: true
    t.index ["workspace_id"], name: "index_categories_on_workspace_id"
  end

  create_table "category_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "category_id", null: false
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "tag_id"], name: "index_category_tags_on_category_id_and_tag_id", unique: true
    t.index ["category_id"], name: "index_category_tags_on_category_id"
    t.index ["tag_id"], name: "index_category_tags_on_tag_id"
  end

  create_table "recurrences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "amount_tolerance_pct", precision: 4, scale: 2, default: "5.0", null: false
    t.string "cadence", null: false
    t.datetime "created_at", null: false
    t.string "descriptor_pattern", null: false
    t.integer "expected_amount_cents"
    t.date "next_expected_at"
    t.string "source", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["account_id"], name: "index_recurrences_on_account_id"
    t.index ["workspace_id", "status"], name: "index_recurrences_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_recurrences_on_workspace_id"
    t.check_constraint "cadence::text = ANY (ARRAY['weekly'::character varying, 'monthly'::character varying, 'yearly'::character varying, 'custom'::character varying]::text[])", name: "recurrences_cadence_check"
    t.check_constraint "expected_amount_cents IS NULL OR expected_amount_cents > 0", name: "recurrences_amount_positive"
    t.check_constraint "source::text = ANY (ARRAY['detected'::character varying, 'manual'::character varying]::text[])", name: "recurrences_source_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'paused'::character varying, 'cancelled'::character varying]::text[])", name: "recurrences_status_check"
  end

  create_table "suggested_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "name", null: false
    t.string "status", default: "pending", null: false
    t.string "tag_names", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "name"], name: "index_suggested_categories_on_workspace_id_and_name", unique: true
    t.index ["workspace_id", "status"], name: "index_suggested_categories_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_suggested_categories_on_workspace_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'accepted'::character varying, 'dismissed'::character varying]::text[])", name: "suggested_categories_status_check"
  end

  create_table "suggested_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "coverage", default: 0, null: false
    t.datetime "created_at", null: false
    t.citext "name", null: false
    t.text "rationale"
    t.string "source", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "name"], name: "index_suggested_tags_on_workspace_id_and_name", unique: true
    t.index ["workspace_id", "status"], name: "index_suggested_tags_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_suggested_tags_on_workspace_id"
    t.check_constraint "source::text = ANY (ARRAY['detected'::character varying, 'manual'::character varying, 'inbox'::character varying]::text[])", name: "suggested_tags_source_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'accepted'::character varying, 'dismissed'::character varying]::text[])", name: "suggested_tags_status_check"
  end

  create_table "tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "icon"
    t.citext "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "name"], name: "index_tags_on_workspace_id_and_name", unique: true
    t.index ["workspace_id"], name: "index_tags_on_workspace_id"
  end

  create_table "transaction_edits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "edited_by_membership_id", null: false
    t.string "field_name", null: false
    t.jsonb "new_value"
    t.jsonb "old_value"
    t.uuid "transaction_id", null: false
    t.datetime "updated_at", null: false
    t.index ["edited_by_membership_id"], name: "index_transaction_edits_on_edited_by_membership_id"
    t.index ["transaction_id", "created_at"], name: "index_transaction_edits_on_transaction_id_and_created_at"
    t.index ["transaction_id"], name: "index_transaction_edits_on_transaction_id"
  end

  create_table "transaction_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.uuid "transaction_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_transaction_tags_on_tag_id"
    t.index ["transaction_id", "tag_id"], name: "index_transaction_tags_on_transaction_id_and_tag_id", unique: true
    t.index ["transaction_id"], name: "index_transaction_tags_on_transaction_id"
  end

  create_table "transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "ai_confidence", precision: 3, scale: 2
    t.jsonb "ai_suggestion"
    t.integer "amount_cents", null: false
    t.datetime "consolidated_at"
    t.datetime "created_at", null: false
    t.uuid "created_by_membership_id"
    t.string "currency", limit: 3, default: "BRL", null: false
    t.string "direction", null: false
    t.virtual "external_transaction_id", type: :text, as: "(source_metadata ->> 'id'::text)", stored: true
    t.text "improved_title"
    t.uuid "installment_group_id"
    t.integer "installment_number", limit: 2
    t.integer "installment_total", limit: 2
    t.integer "lock_version", default: 0, null: false
    t.date "occurred_at", null: false
    t.text "original_description", null: false
    t.uuid "parent_transaction_id"
    t.datetime "rejected_at"
    t.string "source", null: false
    t.jsonb "source_metadata"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["account_id", "external_transaction_id"], name: "index_transactions_on_account_and_external_id", unique: true, where: "(external_transaction_id IS NOT NULL)"
    t.index ["account_id", "occurred_at"], name: "index_transactions_on_account_id_and_occurred_at"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["created_by_membership_id"], name: "index_transactions_on_created_by_membership_id"
    t.index ["installment_group_id"], name: "index_transactions_on_installment_group_id"
    t.index ["parent_transaction_id"], name: "index_transactions_on_parent_transaction_id"
    t.index ["workspace_id", "status", "occurred_at"], name: "index_transactions_on_workspace_status_occurred", order: { occurred_at: :desc }
    t.index ["workspace_id"], name: "index_transactions_on_workspace_id"
    t.check_constraint "(installment_number IS NULL) = (installment_total IS NULL)", name: "transactions_installment_pair_check"
    t.check_constraint "amount_cents > 0", name: "transactions_amount_positive"
    t.check_constraint "direction::text = ANY (ARRAY['debit'::character varying, 'credit'::character varying]::text[])", name: "transactions_direction_check"
    t.check_constraint "source::text = ANY (ARRAY['automatic_sync'::character varying, 'manual_import'::character varying, 'manual_entry'::character varying, 'installment_generated'::character varying]::text[])", name: "transactions_source_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'consolidated'::character varying, 'rejected'::character varying, 'split'::character varying]::text[])", name: "transactions_status_check"
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
    t.jsonb "onboarding_state", default: {"status"=>"not_started"}, null: false
    t.datetime "updated_at", null: false
    t.index "((onboarding_state ->> 'status'::text))", name: "index_workspaces_on_onboarding_status"
    t.index ["created_by_user_id"], name: "index_workspaces_on_created_by_user_id"
  end

  add_foreign_key "accounts", "bank_connections"
  add_foreign_key "accounts", "workspace_memberships", column: "owner_membership_id"
  add_foreign_key "accounts", "workspaces"
  add_foreign_key "ai_learned_rules", "workspaces"
  add_foreign_key "bank_connection_syncs", "bank_connections"
  add_foreign_key "bank_connections", "workspace_memberships", column: "owner_membership_id"
  add_foreign_key "bank_connections", "workspaces"
  add_foreign_key "categories", "workspaces"
  add_foreign_key "category_tags", "categories"
  add_foreign_key "category_tags", "tags"
  add_foreign_key "recurrences", "accounts"
  add_foreign_key "recurrences", "workspaces"
  add_foreign_key "suggested_categories", "workspaces"
  add_foreign_key "suggested_tags", "workspaces"
  add_foreign_key "tags", "workspaces"
  add_foreign_key "transaction_edits", "transactions"
  add_foreign_key "transaction_edits", "workspace_memberships", column: "edited_by_membership_id"
  add_foreign_key "transaction_tags", "tags"
  add_foreign_key "transaction_tags", "transactions"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "transactions", column: "parent_transaction_id"
  add_foreign_key "transactions", "workspace_memberships", column: "created_by_membership_id"
  add_foreign_key "transactions", "workspaces"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
  add_foreign_key "workspaces", "users", column: "created_by_user_id"
end
