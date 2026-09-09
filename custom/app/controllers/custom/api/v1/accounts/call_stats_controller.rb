# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        class CallStatsController < ::Api::V1::Accounts::BaseController
          before_action :check_authorization

          DEFAULT_WINDOW = 30.days

          def index
            return render_invalid_grouping if grouping.blank?

            render json: Custom::Voice::CallStatsBuilder.new(
              account: Current.account,
              group_by: grouping,
              date_range: date_range,
              inbox_id: params[:inbox_id].presence
            ).perform
          end

          private

          # Reuses the reports policy, which Custom::ReportPolicy already widens
          # to agents holding report_manage. These figures rank agents against
          # each other, so they are not for every agent to read.
          def check_authorization
            authorize :report, :view?
          end

          def grouping
            @grouping ||= params[:group_by].to_s.presence_in(
              Custom::Voice::CallStatsBuilder::GROUPINGS.map(&:to_s)
            )
          end

          def render_invalid_grouping
            render json: {
              error: "group_by must be one of: #{Custom::Voice::CallStatsBuilder::GROUPINGS.join(', ')}"
            }, status: :unprocessable_entity
          end

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
