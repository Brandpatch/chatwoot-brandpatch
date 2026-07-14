# [brandpatch]
class AddDebounceDelayToWebhooks < ActiveRecord::Migration[7.1]
  def change
    add_column :webhooks, :debounce_delay, :integer, default: 0, null: false
  end
end
