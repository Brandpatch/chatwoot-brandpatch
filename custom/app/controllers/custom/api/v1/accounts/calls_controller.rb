# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        class CallsController < ::Api::V1::Accounts::BaseController
          def index
            result = Custom::CallFinder.new(Current.user, Current.account, params).perform
            @calls = result[:calls]
            @calls_count = result[:count]
          end
        end
      end
    end
  end
end
