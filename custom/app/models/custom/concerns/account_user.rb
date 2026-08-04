module Custom::Concerns::AccountUser
  extend ActiveSupport::Concern

  included do
    belongs_to :custom_role, optional: true, class_name: 'Custom::CustomRole', inverse_of: :account_users
  end
end
