# frozen_string_literal: true

class AddBrandpatchVoiceLanguagesToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    # [brandpatch] Which languages this agent speaks, for the voice IVR's
    # language routing (Custom::Voice::CallRouter). Own column, same shape as
    # custom_roles.permissions (text array) — no Enterprise counterpart exists
    # for this, so no naming collision to avoid here.
    #
    # Default is ['es'], not []: everyone speaks Spanish until told
    # otherwise, so loading the ~42 existing agents is "mark who also speaks
    # English" rather than "mark everyone's language from scratch". Postgres
    # 11+ applies a column default to existing rows on ADD COLUMN, not just
    # to future inserts, so this reaches the current agents too — no
    # separate backfill migration needed.
    add_column :account_users, :brandpatch_voice_languages, :text, array: true, default: ['es'], null: false
  end
end
