# frozen_string_literal: true

module Custom
  module Voice
    class StatusUpdateService
      pattr_initialize [:account!, :call_sid!, :call_status, { payload: {} }]

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

        Custom::Voice::CallStatus::Manager.new(call: call).process_status_update(
          normalized_status,
          duration: payload_duration,
          timestamp: payload_timestamp,
          end_reason: end_reason_for(normalized_status)
        )
      end

      private

      # This webhook tracks the customer's leg — the agent dials in on a second
      # leg with its own SID, which is not the one stored on the call. A call
      # that was connected and now reads completed is the customer's line
      # closing, so they are the one who hung up. Only that one: busy and
      # no-answer mean the customer never picked up, which the status already
      # says and nobody hung up on.
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
