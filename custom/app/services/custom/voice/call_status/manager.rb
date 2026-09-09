# frozen_string_literal: true

module Custom
  module Voice
    module CallStatus
      class Manager
        pattr_initialize [:call!]

        def process_status_update(status, duration: nil, timestamp: nil)
          return unless Custom::Call::STATUSES.include?(status)
          return if call.status == status
          return if Custom::Call::TERMINAL_STATUSES.include?(call.status)

          apply_call_updates!(status, duration: duration, timestamp: timestamp)
          close_open_ring_attempt! if Custom::Call::TERMINAL_STATUSES.include?(status)
          call.conversation.update!(last_activity_at: Time.zone.now)
          call.message&.touch # rubocop:disable Rails/SkipsModelValidations
        end

        private

        # A turn still open when the call ends terminally was cut short by the
        # caller giving up, not by the agent. Paths where the agent owns the
        # outcome (answered, rejected, ring timeout) close the turn themselves
        # before reaching here, and the first close wins.
        def close_open_ring_attempt!
          Custom::Voice::RingAttemptTracker.close!(call, Custom::CallRingAttempt::CALLER_HANGUP)
        end

        def apply_call_updates!(status, duration:, timestamp:)
          attrs = { status: status }
          ts = timestamp || now_seconds

          if status == 'in_progress'
            started_at = Time.zone.at(ts)
            attrs[:started_at] = started_at if call.started_at.nil? || started_at < call.started_at
          elsif Custom::Call::TERMINAL_STATUSES.include?(status)
            call.ended_at = ts
            attrs[:meta] = call.meta
            attrs[:duration_seconds] = resolved_duration(duration, ts)
          end

          call.update!(attrs)
        end

        def resolved_duration(provided_duration, timestamp)
          return provided_duration if provided_duration
          return unless call.started_at

          [timestamp - call.started_at.to_i, 0].max
        end

        def now_seconds
          Time.zone.now.to_i
        end
      end
    end
  end
end
