# frozen_string_literal: true

module Custom
  module Concerns
    module Message
      extend ActiveSupport::Concern

      included do
        has_one :custom_call, class_name: 'Custom::Call', foreign_key: :message_id,
                              dependent: :nullify, inverse_of: :message
        scope :with_custom_call, -> { includes(custom_call: [:contact, inbox: :channel]) }
      end
    end
  end
end
