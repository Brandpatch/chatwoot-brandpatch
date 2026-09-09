# frozen_string_literal: true

module Custom
  module Concerns
    module Account
      extend ActiveSupport::Concern

      included do
        has_many :brandpatch_custom_roles, class_name: 'Custom::CustomRole', foreign_key: :account_id,
                                          inverse_of: :account, dependent: :destroy_async
        has_many :custom_calls, class_name: 'Custom::Call', dependent: :destroy_async
      end
    end
  end
end
