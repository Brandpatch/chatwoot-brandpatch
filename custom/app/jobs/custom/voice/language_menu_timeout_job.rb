# frozen_string_literal: true

module Custom
  module Voice
    # Inbound calls get no terminal status callback from Twilio at all — the
    # same gap that causes phantom calls — so nobody tells us if the caller
    # hangs up while the voice IVR's language menu (T4) is still playing.
    # Left alone, that call would sit at ringing with routing_deferred true
    # until ReconcileStuckCallsJob catches it 15 minutes later, and in the
    # meantime Conference::Manager#assign_waiting_calls! already knows to
    # leave it alone (see Custom::Call#routing_deferred?) — it just never
    # gets cleaned up on its own.
    class LanguageMenuTimeoutJob < ApplicationJob
      queue_as :default

      # Comfortably above the menu's own worst case: two attempts, each a
      # ~3s Gather timeout plus the prompt's own TTS playback — around 15-20s
      # end to end. A caller still legitimately in the menu at 30s would
      # already have been routed by the menu's own fallback to Spanish; this
      # job is for the one who hung up, not the one still listening.
      ABANDON_TIMEOUT = 30

      def perform(call_id)
        call = Custom::Call.find_by(id: call_id)
        return unless call
        return if call.terminal?
        return unless call.routing_deferred?

        end_provider_leg(call)
        Custom::Voice::CallStatus::Manager.new(call: call).process_status_update('no_answer')
      end

      private

      # Same move as Custom::Voice::Provider::Twilio::ConferenceService
      # #end_provider_leg, duplicated rather than reused: that method exists
      # to tear down a conference leg, and there is no conference yet here —
      # the caller never left the menu. The caller has usually already hung
      # up by the time this runs, so Twilio has already ended the call on its
      # own and rejects the update; that is the expected outcome, not a
      # failure.
      def end_provider_leg(call)
        return if call.provider_call_id.blank?

        call.inbox.channel.client.calls(call.provider_call_id).update(status: 'completed')
      rescue ::Twilio::REST::RestError => e
        Rails.logger.info("VOICE_LANGUAGE_MENU_END_LEG_SKIPPED: call=#{call.id} sid=#{call.provider_call_id} #{e.message}")
      end
    end
  end
end
