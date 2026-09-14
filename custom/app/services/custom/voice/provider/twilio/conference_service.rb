# frozen_string_literal: true

module Custom
  module Voice
    module Provider
      module Twilio
        class ConferenceService
          pattr_initialize [:call!]

          def ensure_conference_sid
            return call.conference_sid if call.conference_sid.present?

            call.update!(conference_sid: call.default_conference_sid)
            call.conference_sid
          end

          def mark_agent_joined(user:)
            claim_call!(user)
            call.assign_conversation_to!(user.id)
          end

          def end_conference
            end_provider_leg
            return if call.conference_sid.blank?

            client = call.inbox.channel.client
            client
              .conferences
              .list(friendly_name: call.conference_sid, status: 'in-progress')
              .each { |conf| client.conferences(conf.sid).update(status: 'completed') }
          end

          private

          # An outbound leg the callee has not picked up yet rings outside the
          # conference, so completing the conference leaves their phone ringing.
          # Ending the call resource itself covers that as well as the legs that
          # did join. Twilio rejects the update once a leg is already finished,
          # which is the common case here since end_conference also runs on calls
          # the provider has torn down on its own.
          def end_provider_leg
            return if call.provider_call_id.blank?

            call.inbox.channel.client.calls(call.provider_call_id).update(status: 'completed')
          rescue ::Twilio::REST::RestError => e
            Rails.logger.info("VOICE_END_LEG_SKIPPED: call=#{call.id} sid=#{call.provider_call_id} #{e.message}")
          end

          # A click that lands on a call that is already over must not leave a
          # trace: crediting the agent here also marks their ring turn answered
          # and hands them the conversation, so an agent who never spoke ends up
          # owning both. Measured in production: 13 inbound calls sat at
          # no_answer with an agent on them, and 12 of those conversations were
          # assigned to somebody who never talked. The conference webhook's own
          # claim path has always checked this; only the click path did not.
          def claim_call!(user)
            call.with_lock do
              raise CustomExceptions::CallAlreadyEnded if call.terminal?
              raise_already_accepted!(call.accepted_by_agent) if claimed_by_other_agent?(user)

              call.update!(accepted_by_agent: user) if call.accepted_by_agent_id != user.id
            end

            # The agent's own click is the authoritative "I took this call" signal.
            # The Twilio join webhook can carry a different identity (a stale
            # browser Device, or a late join after the turn already escalated),
            # which would otherwise leave a real answer unrecorded and let the
            # turn fall through to the terminal catch-all.
            Custom::Voice::RingAttemptTracker.record_answer!(call, user.id)
          end

          def claimed_by_other_agent?(user)
            call.accepted_by_agent_id.present? && call.accepted_by_agent_id != user.id
          end

          def raise_already_accepted!(agent)
            raise CustomExceptions::CallAlreadyAccepted.new(agent_name: agent&.available_name || agent&.name)
          end
        end
      end
    end
  end
end
