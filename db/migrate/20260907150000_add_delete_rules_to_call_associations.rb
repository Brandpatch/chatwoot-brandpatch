# frozen_string_literal: true

# Deleting a voice inbox, a conversation with calls, an account or a user used
# to fail, and to fail quietly. The associations that clean call rows up run
# through `dependent: :destroy_async`, which deletes the parent first and its
# children in a background job, so the references the voice channel added stood
# in the way of the parent's own delete. Because it happened inside Sidekiq the
# UI reported nothing: the inbox was gone from the list and its calls were left
# pointing at a row that no longer existed.
#
# The behaviour belongs here rather than in Ruby callbacks. Stated at this level
# it holds for every path that deletes -- whatever order the async jobs happen
# to run in, a `delete_all`, or somebody working from the console.
class AddDeleteRulesToCallAssociations < ActiveRecord::Migration[7.1]
  def up
    # A ring turn means nothing without the call it belongs to, and neither of
    # them means anything without the account.
    replace_delete_rule :call_ring_attempts, :calls, :call_id, :cascade
    replace_delete_rule :call_ring_attempts, :accounts, :account_id, :cascade
    # A turn is the record of what one agent did with one offer, so it goes when
    # the agent does. Its own column is NOT NULL, so there is nothing to null.
    replace_delete_rule :call_ring_attempts, :users, :agent_id, :cascade
    # The call outlives the agent: it still carries the duration, the recording
    # and who answered it. Only the pointer to whoever it happened to be ringing
    # for at that moment is dropped -- which is also what accepted_by_agent_id,
    # the column beside it, has always done by carrying no reference at all.
    replace_delete_rule :calls, :users, :current_ring_agent_id, :nullify
  end

  def down
    replace_delete_rule :call_ring_attempts, :calls, :call_id, nil
    replace_delete_rule :call_ring_attempts, :accounts, :account_id, nil
    replace_delete_rule :call_ring_attempts, :users, :agent_id, nil
    replace_delete_rule :calls, :users, :current_ring_agent_id, nil
  end

  private

  # Postgres has no ALTER for a constraint's delete rule, so it is dropped and
  # written again.
  def replace_delete_rule(table, to_table, column, on_delete)
    remove_foreign_key table, column: column
    add_foreign_key table, to_table, column: column, on_delete: on_delete
  end
end
