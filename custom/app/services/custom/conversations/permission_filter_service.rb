module Custom::Conversations::PermissionFilterService
  def perform
    return brandpatch_filter_by_permissions(brandpatch_permissions) if brandpatch_user_has_custom_role?

    super
  end

  private

  # [brandpatch] Prefixed to avoid colliding with the identically-named private
  # methods in enterprise/app/services/enterprise/conversations/permission_filter_service.rb
  # (both modules are prepended onto the same Conversations::PermissionFilterService
  # class, and Ruby resolves unqualified calls from the front of the ancestor
  # chain regardless of which module's code is calling — see the Custom::ConversationPolicy
  # fix from the 2.3 security review for the full explanation).
  #
  # Also deliberately does NOT use account_user.permissions (the method Enterprise
  # overrides via AccountUser.prepend_mod_with) — that override reads the old
  # `custom_role` association, not ours, so relying on it here would silently
  # return the wrong (empty) permission set for our own feature.
  def brandpatch_user_has_custom_role?
    user_role == 'agent' && account_user&.brandpatch_custom_role_id.present?
  end

  def brandpatch_permissions
    account_user&.brandpatch_custom_role&.permissions || []
  end

  def brandpatch_filter_by_permissions(permissions)
    # Permission-based filtering with hierarchy:
    # conversation_manage > conversation_unassigned_manage > conversation_participating_manage
    if permissions.include?('conversation_manage')
      accessible_conversations
    elsif permissions.include?('conversation_unassigned_manage')
      brandpatch_filter_unassigned_and_mine
    elsif permissions.include?('conversation_participating_manage')
      brandpatch_filter_participating_and_mine
    else
      Conversation.none
    end
  end

  def brandpatch_filter_participating_and_mine
    conversations = accessible_conversations
    participant_conversation_ids = ConversationParticipant.where(account_id: account.id, user_id: user.id).select(:conversation_id)

    conversations
      .where(assignee_id: user.id)
      .or(conversations.where(id: participant_conversation_ids))
  end

  def brandpatch_filter_unassigned_and_mine
    accessible_conversations.where(assignee_id: [nil, user.id])
  end
end
