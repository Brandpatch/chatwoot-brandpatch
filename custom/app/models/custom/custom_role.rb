class Custom::CustomRole < ApplicationRecord
  self.table_name = 'custom_roles'

  belongs_to :account
  has_many :account_users, dependent: :nullify, foreign_key: :brandpatch_custom_role_id, inverse_of: :brandpatch_custom_role

  PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    contact_manage
    report_manage
    knowledge_base_manage
  ].freeze

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validate :permissions_are_valid

  # [brandpatch] account_users.dependent: :nullify above runs as a bulk SQL
  # UPDATE, which skips ActiveRecord callbacks on AccountUser entirely — so
  # the filtered-unread-count cache would go stale for every agent who had
  # this role destroyed out from under them unless we invalidate it here.
  before_destroy :capture_affected_user_ids, prepend: true
  after_destroy_commit :invalidate_unread_count_visibility_destroy

  # Editing an already-assigned role's permissions doesn't change any
  # account_users row at all, so AccountUser's own change-tracking callbacks
  # never fire for this case either — invalidate explicitly here too.
  after_update_commit :invalidate_unread_count_visibility_update, if: :permissions_changed_since_last_save?

  private

  def permissions_are_valid
    invalid_permissions = Array(permissions) - PERMISSIONS
    return if invalid_permissions.empty?

    errors.add(:permissions, "contains invalid values: #{invalid_permissions.join(', ')}")
  end

  def permissions_changed_since_last_save?
    previous_changes.key?('permissions')
  end

  def capture_affected_user_ids
    @affected_user_ids = account_users.pluck(:user_id)
  end

  def invalidate_unread_count_visibility_update
    invalidate_unread_count_visibility(account_users.pluck(:user_id))
  end

  def invalidate_unread_count_visibility_destroy
    invalidate_unread_count_visibility(@affected_user_ids)
  end

  def invalidate_unread_count_visibility(user_ids)
    invalidator = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account)
    visibility_changed = invalidator.users_visibility_changed!(user_ids: user_ids)

    dispatch_account_cache_invalidated if visibility_changed
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end
