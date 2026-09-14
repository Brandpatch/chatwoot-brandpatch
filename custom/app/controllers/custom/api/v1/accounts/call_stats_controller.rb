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
            # Checked here, in this format, rather than trusting the shared
            # handler: it answers a refusal with `render json:`, which does not
            # stop a request whose format is csv, so the guard raised and the
            # file was served anyway. These figures cover every agent.
            return head :unauthorized unless authorized_to_view_reports?
            return render_invalid_grouping if grouping.blank?

            @stats = stats
            @grouping = grouping
            # Resolved here, not read from params in the template: both ends are
            # optional and fall back to a default window, so the file has to
            # state the period actually used rather than what was asked for.
            @period_since = local_date(date_range.first)
            @period_until = local_date(date_range.last)

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

          # Same policy the guard uses, asked directly so the answer is a
          # boolean this action can act on instead of an exception someone else
          # renders.
          #
          # Rooted with :: on purpose. Inside module Custom, a bare ReportPolicy
          # resolves to Custom::ReportPolicy first — which exists, and is the
          # module prepended onto the real one, not a class. Calling .new on it
          # is what turned the refusal into a 500.
          def authorized_to_view_reports?
            ::ReportPolicy.new(pundit_user, :report).view?
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

          # The dashboard works out the range in the reader's own time zone, so
          # the end of a day arrives as an instant that is already the next day
          # in UTC — for UTC-4, 23:59:59 of the 12th is 03:59:59 of the 13th.
          # Printing that instant's UTC date made the file claim a day nobody
          # asked for. The offset comes with the request so the dates read back
          # the way the screen showed them, wherever the reader is.
          def local_date(time)
            (time + utc_offset_minutes.minutes).utc.to_date
          end

          # Minutes to add to UTC, as the browser's getTimezoneOffset reports it
          # inverted. Clamped to the real range so a junk value cannot shift the
          # header into a different day.
          def utc_offset_minutes
            @utc_offset_minutes ||= params[:utc_offset].to_i.clamp(-14 * 60, 14 * 60)
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
