module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    # [brandpatch] Named distinctly from Enterprise::Concerns::Account's own
    # `has_many :custom_roles` (which points at the unnamespaced, EE-licensed
    # CustomRole model) — both concerns get included into Account, and reusing
    # the same association name would silently overwrite one with the other.
    has_many :brandpatch_custom_roles, class_name: 'Custom::CustomRole', foreign_key: :account_id,
                                        inverse_of: :account, dependent: :destroy_async
  end
end
