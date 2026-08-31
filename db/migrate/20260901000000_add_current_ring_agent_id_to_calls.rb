# frozen_string_literal: true

class AddCurrentRingAgentIdToCalls < ActiveRecord::Migration[7.1]
  def change
    add_reference :calls, :current_ring_agent, foreign_key: { to_table: :users }, null: true
  end
end
