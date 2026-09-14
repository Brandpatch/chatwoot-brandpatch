# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        # An agent's own call figures, for the strip above their call list.
        #
        # Kept apart from CallStatsController rather than added to it as another
        # action. That controller is closed behind authorize :report, :view?
        # because its figures rank agents against each other, and an action that
        # deliberately skips that check would have to be carved out of the
        # before_action — leaving a hole for the next action added there to fall
        # into. Here the rule has no exceptions: the reader is the subject.
        class MyCallStatsController < ::Api::V1::Accounts::BaseController
          DEFAULT_WINDOW = 30.days

          def show
            render json: Custom::Voice::CallStatsBuilder.new(
              account: Current.account,
              date_range: date_range,
              inbox_id: params[:inbox_id].presence
            ).agent_summary(Current.user.id)
          end

          private

          # Read from the session, never from the request. Taking an agent_id
          # off the params is what would turn this back into the comparative
          # report it exists to avoid.
          def date_range
            from = timestamp(params[:since]) || DEFAULT_WINDOW.ago
            to = timestamp(params[:until]) || Time.zone.now
            from..to
          end

          def timestamp(value)
            epoch = value.to_i
            epoch.positive? ? Time.zone.at(epoch) : nil
          end
        end
      end
    end
  end
end
