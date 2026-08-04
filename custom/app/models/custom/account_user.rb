module Custom::AccountUser
  private

  # [brandpatch] AccountUser's own filtered_unread_count_visibility_changed?
  # only watches the Enterprise-owned `custom_role_id` column, not ours —
  # without this, reassigning brandpatch_custom_role to a single agent would
  # leave their cached unread count stale. Kept private, matching the
  # visibility of the base method it overrides.
  def filtered_unread_count_visibility_changed?
    super || previous_changes.key?('brandpatch_custom_role_id')
  end
end
