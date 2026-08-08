# Enable custom_roles_brandpatch for existing accounts.
# We don't need to update ACCOUNT_LEVEL_FEATURE_DEFAULTS or clear GlobalConfig
# cache here because custom_roles_brandpatch already has `enabled: true` in
# features.yml — ConfigLoader (enhanced onto db:migrate) handles that for
# accounts created from now on. This migration only backfills accounts that
# already existed before this feature flag did.
class EnableCustomRolesBrandpatchForExistingAccounts < ActiveRecord::Migration[7.1]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('custom_roles_brandpatch') }
    end
  end
end
