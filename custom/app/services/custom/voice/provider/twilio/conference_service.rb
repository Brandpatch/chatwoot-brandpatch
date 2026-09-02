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
            assign_conversation!(user)
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

          def claim_call!(user)
            call.with_lock do
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

          def assign_conversation!(user)
            conversation = call.conversation
            return if conversation.assigned_entity.present?

            ::Conversations::AssignmentService.new(conversation: conversation, assignee_id: user.id).perform
          end
        end
      end
    end
  end
end
