class AddBrandpatchCustomRoleToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    # [brandpatch] Own column, deliberately separate from account_users.custom_role_id
    # (used by Enterprise::ConversationPolicy) so our Custom Roles feature never
    # activates that Enterprise-licensed authorization code.
    add_reference :account_users, :brandpatch_custom_role, optional: true
  end
end
