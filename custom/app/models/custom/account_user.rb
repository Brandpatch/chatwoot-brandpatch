module Custom::AccountUser
  # [brandpatch] Enterprise::AccountUser#permissions only looks at the
  # Enterprise-owned `custom_role` association, so without this override an
  # agent assigned one of our own Custom Roles would still be serialized to
  # the frontend with only ['agent'] as their permissions — breaking every
  # <Policy permissions="..."> UI check that depends on this array.
  def permissions
    brandpatch_custom_role.present? ? (brandpatch_custom_role.permissions + ['custom_role']) : super
  end

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
