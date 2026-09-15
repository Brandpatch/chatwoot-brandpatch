# frozen_string_literal: true

module Custom
  module Voice
    # A call whose final provider callback never arrives stays non-terminal
    # forever, and nothing else closes it: the ring timeout job only expires a
    # call that is still 'ringing', and outbound calls never even arm it.
    #
    # That is not just an untidy row. The router reads Custom::Call.active to
    # decide who is busy, so one stuck record takes an agent out of voice
    # routing indefinitely, in silence. Found in production on 2026-09-15:
    # three stuck calls, two of them 30 hours old, and the two agents on them
    # had not been offered a single call since.
    class ReconcileStuckCallsJob < ApplicationJob
      queue_as :scheduled_jobs

      # How long a call may sit non-terminal before we start asking the provider
      # about it. Long calls are normal — one ran 75 minutes — so this only
      # decides when to start asking, never whether to close: nothing closes
      # unless the provider itself reports the call over.
      STUCK_AFTER = 15.minutes

      def perform
        Custom::Call.active.twilio.where(created_at: ..STUCK_AFTER.ago).find_each { |call| reconcile(call) }
      end

      private

      def reconcile(call)
        remote = call.inbox.channel.client.calls(call.provider_call_id).fetch
        status = Custom::Voice::StatusUpdateService::TWILIO_STATUS_MAP[remote.status]
        return unless status && Custom::Call::TERMINAL_STATUSES.include?(status)
        # Without it there is no honest timestamp to close on, and the manager
        # would compute a duration spanning however long the record sat stuck.
        return if remote.end_time.blank?

        Custom::Voice::CallStatus::Manager
          .new(call: call)
          .process_status_update(status, duration: remote.duration.to_i, timestamp: remote.end_time.to_i)

        Rails.logger.info(
          "VOICE_RECONCILED_STUCK_CALL: call=#{call.id} direction=#{call.direction} " \
          "provider_status=#{remote.status} status=#{status} duration=#{remote.duration}"
        )
      rescue ::Twilio::REST::RestError => e
        Rails.logger.info("VOICE_RECONCILE_SKIPPED: call=#{call.id} #{e.message}")
      end
    end
  end
end
