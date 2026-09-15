# frozen_string_literal: true

module Custom
  module Voice
    class StatusUpdateService
      pattr_initialize [:account!, :call_sid!, :call_status, { payload: {} }]

      # Enough to tell one ending from another without copying the customer's
      # number into the logs.
      LOGGED_PAYLOAD_KEYS = %w[CallStatus ErrorCode ErrorMessage SipResponseCode Direction].freeze

      TWILIO_STATUS_MAP = {
        'queued'      => 'ringing',
        'initiated'   => 'ringing',
        'ringing'     => 'ringing',
        'in-progress' => 'in_progress',
        'inprogress'  => 'in_progress',
        'answered'    => 'in_progress',
        'completed'   => 'completed',
        'busy'        => 'no_answer',
        'no-answer'   => 'no_answer',
        'failed'      => 'failed',
        # Twilio reports canceled when a leg is terminated before it was
        # answered, which is what hanging up on a ringing call does. Keeping
        # failed for that would hide real failures (bad number, carrier
        # rejection) among deliberate cancellations.
        'canceled'    => 'no_answer'
      }.freeze

      def perform
        normalized_status = normalize_status(call_status)
        return if normalized_status.blank?

        call = Custom::Call.where(account_id: account.id).find_by(provider: :twilio, provider_call_id: call_sid)
        return unless call

        log_failure_payload(call) if error_code.present?

        Custom::Voice::CallStatus::Manager.new(call: call).process_status_update(
          normalized_status,
          duration: payload_duration,
          timestamp: payload_timestamp,
          end_reason: end_reason_for(normalized_status),
          failure: failure_for(call)
        )
      end

      private

      # Twilio says why a call never connected, and until now this webhook threw
      # it away — so a call to a number that does not exist read as "the contact
      # didn't pick up", and the agent kept dialling it.
      #
      # Outbound only. An inbound call that fails did so before reaching us, and
      # there is nothing the agent could do about it.
      def failure_for(call)
        return unless call.outgoing?
        return if error_code.blank?

        { reason: Custom::Call.failure_reason_for(error_code), error_code: error_code.to_s }
      end

      def error_code
        return unless payload.is_a?(Hash)

        @error_code ||= payload['ErrorCode'].presence || payload['error_code'].presence
      end

      # Logged whole because the mapping is partial by design: an ending nobody
      # anticipated is easier to name from the payload that produced it than
      # from a code alone.
      def log_failure_payload(call)
        Rails.logger.info(
          "[voice] call=#{call.id} sid=#{call_sid} status=#{call_status} " \
          "error_code=#{error_code} payload=#{payload.slice(*LOGGED_PAYLOAD_KEYS)}"
        )
      end

      # This webhook tracks the customer's leg — the agent dials in on a second
      # leg with its own SID, which is not the one stored on the call. So
      # completed here is the customer's line closing, whether or not an agent
      # had picked up: a caller who gives up mid-ring lands on completed too,
      # and they did hang up. The bubble only shows the reason on a call
      # somebody took, so the unanswered case never reaches a reader.
      #
      # Only completed. busy and no-answer mean the customer never picked up at
      # all, which the status already says and which nobody hung up on.
      def end_reason_for(status)
        Custom::Call::CALLER_HANGUP if status == 'completed'
      end

      def normalize_status(status)
        return if status.to_s.strip.empty?

        TWILIO_STATUS_MAP[status.to_s.downcase]
      end

      def payload_duration
        return unless payload.is_a?(Hash)

        duration = payload['CallDuration'] || payload['call_duration']
        duration&.to_i
      end

      def payload_timestamp
        return unless payload.is_a?(Hash)

        ts = payload['Timestamp'] || payload['timestamp']
        return unless ts

        Time.zone.parse(ts).to_i
      rescue ArgumentError
        nil
      end
    end
  end
end
