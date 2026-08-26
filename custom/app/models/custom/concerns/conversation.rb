# frozen_string_literal: true

module Custom
  module Concerns
    module Conversation
      extend ActiveSupport::Concern

      included do
        has_many :custom_calls, class_name: 'Custom::Call', dependent: :destroy_async
      end
    end
  end
end
