# frozen_string_literal: true

class CreateCallRingAttempts < ActiveRecord::Migration[7.1]
  def change
    create_table :call_ring_attempts do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :call, null: false, foreign_key: true, index: false
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.datetime :rang_at, null: false
      t.datetime :ended_at
      t.string :outcome
      t.timestamps
    end

    # Locating the still-open turn for a call, on every assignment and close.
    add_index :call_ring_attempts, [:call_id, :ended_at]
    # Per-agent report aggregation over a date range.
    add_index :call_ring_attempts, [:account_id, :rang_at]
  end
end
