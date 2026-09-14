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

            render json: stats
          end

          # Same figures as index, with the same filters, so the file matches
          # what the reader had on screen when they asked for it.
          #
          # Built here rather than in the browser, where the rows already are:
          # agent names are user-supplied text, and one starting with =, +, -
          # or @ runs as a formula when the file opens in Excel. CSVSafe is what
          # every other export in this app uses against that, and this file
          # opens on an administrator's machine.
          def csv
            return render_invalid_grouping if grouping.blank?

            @stats = stats
            @grouping = grouping
            # Resolved here, not read from params in the template: both ends are
            # optional and fall back to a default window, so the file has to
            # state the period actually used rather than what was asked for.
            #
            # Printed in UTC, like every other export. The end of the range is
            # 23:59:59 of the last day, and reading that through the app's time
            # zone rolls it into the next one — the file claimed a day the
            # reader had not asked for, and disagreed with its own name.
            @period_since = date_range.first.utc.to_date
            @period_until = date_range.last.utc.to_date

            # No Content-Disposition: the dashboard reads the body and saves it
            # through a blob, naming the file itself with the same helper every
            # other report uses. A name here would be dead weight that could
            # drift from the real one.
            response.headers['Content-Type'] = 'text/csv'
            render layout: false, formats: [:csv]
          end

          private

          def stats
            Custom::Voice::CallStatsBuilder.new(
              account: Current.account,
              group_by: grouping,
              date_range: date_range,
              inbox_id: params[:inbox_id].presence
            ).perform
          end

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
