class Custom::CustomRole < ApplicationRecord
  self.table_name = 'custom_roles'

  belongs_to :account
  has_many :account_users, dependent: :nullify, foreign_key: :custom_role_id, inverse_of: :custom_role

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

  private

  def permissions_are_valid
    invalid_permissions = Array(permissions) - PERMISSIONS
    return if invalid_permissions.empty?

    errors.add(:permissions, "contains invalid values: #{invalid_permissions.join(', ')}")
  end
end
