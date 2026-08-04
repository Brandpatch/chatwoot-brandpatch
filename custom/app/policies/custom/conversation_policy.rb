module Custom::ConversationPolicy
  def show?
    return false unless super
    return true unless brandpatch_custom_role_permissions?

    permissions = brandpatch_custom_role_permissions
    return true if brandpatch_manage_all_conversations?(permissions)
    return true if brandpatch_permits_unassigned_manage?(permissions)

    brandpatch_permits_participating?(permissions)
  end

  private

  # [brandpatch] Prefixed to avoid colliding with the identically-purposed
  # private methods in enterprise/app/policies/enterprise/conversation_policy.rb.
  # Both modules are prepended onto the same ConversationPolicy class, and Ruby
  # resolves unqualified method calls from the front of the ancestor chain
  # regardless of which module's code is calling — same names would make
  # Enterprise's own `show?` silently call into (and depend on) our methods.
  def brandpatch_manage_all_conversations?(permissions)
    permissions.include?('conversation_manage')
  end

  def brandpatch_permits_unassigned_manage?(permissions)
    return false unless permissions.include?('conversation_unassigned_manage')

    brandpatch_unassigned_conversation? || assigned_to_user?
  end

  def brandpatch_permits_participating?(permissions)
    return false unless permissions.include?('conversation_participating_manage')

    assigned_to_user? || participant?
  end

  def brandpatch_unassigned_conversation?
    record.assignee_id.nil?
  end

  def brandpatch_custom_role_permissions?
    account_user&.brandpatch_custom_role_id.present?
  end

  def brandpatch_custom_role_permissions
    account_user&.brandpatch_custom_role&.permissions || []
  end
end
