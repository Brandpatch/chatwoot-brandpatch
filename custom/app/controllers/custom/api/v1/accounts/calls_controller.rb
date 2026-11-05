# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        class CallsController < ::Api::V1::Accounts::BaseController
          # A download covers the period the list is showing, and that period
          # can be a year. Measured against production: 7 days is 12.100 rows
          # and 2,7 s, 30 days is 55.900 rows and 10,7 s, a year is the whole
          # history at ~100.000 rows and roughly 20 s. Production runs a single
          # Puma process with five threads, so an unbounded export parks a
          # fifth of the app for half a minute while it builds.
          #
          # A month is the window the people who asked for this file actually
          # review. Widening it is this constant and nothing else — but past
          # a couple of months the honest answer is a background job that
          # mails the file, the way Account::ContactsExportJob already does.
          MAX_EXPORT_DAYS = 31

          BATCH_SIZE = 500

          # The template stamps every row's time with it.
          helper_method :local_time

          def index
            result = finder.perform
            @calls = result[:calls]
            @calls_count = result[:count]
          end

          # The same calls the list is showing, with the same filters, so the
          # file matches the screen the reader asked it from. Row-level
          # visibility comes with the finder: an agent exports their own calls
          # and an administrator exports the account's, and this action does
          # not have to know the difference.
          #
          # Built here rather than in the browser because the list only ever
          # holds 25 rows at a time, and because contact names are
          # user-supplied text — one starting with =, +, - or @ runs as a
          # formula when the file opens in Excel. CSVSafe is what every other
          # export in this app uses against that.
          def csv
            return render_missing_period if period.blank?
            return render_period_too_wide if period_days > MAX_EXPORT_DAYS

            @calls = finder.filtered.includes(:contact, :conversation, :accepted_by_agent, inbox: :channel)
            @batch_size = BATCH_SIZE
            @period_since = local_time(period.first).to_date
            @period_until = local_time(period.last).to_date

            # No Content-Disposition: the dashboard reads the body and saves it
            # through a blob, naming the file with the same helper every other
            # export uses. A name here would be dead weight that could drift
            # from the real one.
            response.headers['Content-Type'] = 'text/csv'
            render layout: false, formats: [:csv]
          end

          private

          def finder
            @finder ||= Custom::CallFinder.new(Current.user, Current.account, params)
          end

          # Both ends are required rather than defaulted. CallFinder only
          # applies its date filter when it has both, so a missing one would
          # quietly export the entire history and walk straight past the limit
          # above. The page always sends them; a request without them is a
          # mistake worth naming.
          def period
            @period ||= begin
              from = timestamp(params[:since])
              to = timestamp(params[:until])
              from && to && to >= from ? from..to : nil
            end
          end

          def period_days
            ((period.last - period.first) / 1.day).ceil
          end

          def timestamp(value)
            epoch = value.to_i
            epoch.positive? ? Time.zone.at(epoch) : nil
          end

          # The dashboard works out the range in the reader's own time zone, so
          # the end of a day arrives as an instant that is already the next day
          # in UTC — for UTC-4, 23:59:59 of the 12th is 03:59:59 of the 13th.
          # Printing that instant's UTC date made the report CSV claim a day
          # nobody asked for. The offset comes with the request so every time
          # in the file reads the way the screen showed it, wherever the reader
          # is.
          def local_time(time)
            (time + utc_offset_minutes.minutes).utc
          end

          # Minutes to add to UTC, as the browser's getTimezoneOffset reports it
          # inverted. Clamped to the real range so a junk value cannot shift a
          # timestamp into a different day.
          def utc_offset_minutes
            @utc_offset_minutes ||= params[:utc_offset].to_i.clamp(-14 * 60, 14 * 60)
          end

          def render_missing_period
            render json: { error: 'since and until are required, as unix timestamps, with until no earlier than since' },
                   status: :unprocessable_entity
          end

          def render_period_too_wide
            render json: { error: "the exported period cannot be longer than #{MAX_EXPORT_DAYS} days" },
                   status: :unprocessable_entity
          end
        end
      end
    end
  end
end
