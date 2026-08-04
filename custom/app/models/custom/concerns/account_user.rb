module Custom::Concerns::AccountUser
  extend ActiveSupport::Concern

  included do
    # [brandpatch] Deliberately not named/aliased as `custom_role` — that name
    # and its backing `custom_role_id` column are read by
    # Enterprise::ConversationPolicy (see enterprise/app/policies/enterprise/conversation_policy.rb).
    # Keeping our own association and column fully separate ensures that
    # Enterprise-licensed code never activates based on data our own
    # Custom Roles feature creates.
    belongs_to :brandpatch_custom_role, optional: true, class_name: 'Custom::CustomRole',
                                         foreign_key: :brandpatch_custom_role_id, inverse_of: :account_users
  end
end
