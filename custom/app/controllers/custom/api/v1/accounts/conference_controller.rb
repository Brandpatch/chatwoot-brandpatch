# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        class ConferenceController < ::Api::V1::Accounts::BaseController
          before_action :set_voice_inbox_for_conference
          rescue_from CustomExceptions::CallAlreadyAccepted, with: :render_call_already_accepted

          def token
            render json: Custom::Voice::Provider::Twilio::TokenService.new(
              inbox: @voice_inbox,
              user: Current.user,
              account: Current.account
            ).generate
          end

          def create
            call = resolve_call!
            conference_service = Custom::Voice::Provider::Twilio::ConferenceService.new(call: call)
            conference_sid = conference_service.ensure_conference_sid
            conference_service.mark_agent_joined(user: current_user)

            render json: {
              status: 'success',
              id: call.conversation.display_id,
              conference_sid: conference_sid,
              using_webrtc: true
            }
          end

          # The widget sends this for both "I decline" and "I hang up", and only
          # the call's own state tells them apart.
          #
          # finalize_call! runs before the provider teardown on purpose. Ending
          # the conference completes the caller's leg, and Twilio posts the
          # status webhook for it within a couple hundred milliseconds — fast
          # enough to mark the call terminal first, which made finalize_call!
          # bail on its own `next if call.terminal?` and drop the outcome
          # silently.
          def destroy
            call = resolve_call!

            if declining_ringing_call?(call)
              Custom::Voice::CallEscalationService.new(call: call, outcome: Custom::CallRingAttempt::REJECTED).perform
            else
              finalize_call!(call)
              Custom::Voice::Provider::Twilio::ConferenceService.new(call: call).end_conference
              call.broadcast_voice_call_event(:ended, status: call.display_status)
            end

            render json: { status: 'success', id: call.conversation.display_id }
          end

          private

          def resolve_call!
            sid = params[:call_sid].presence
            raise ActionController::ParameterMissing, :call_sid if sid.blank?

            conversation = fetch_conversation_by_display_id
            Custom::Call.where(inbox_id: @voice_inbox.id, provider: :twilio, conversation_id: conversation.id)
                        .find_by!(provider_call_id: sid)
          end

          def set_voice_inbox_for_conference
            @voice_inbox = Current.account.inboxes.find(params[:inbox_id])
            authorize @voice_inbox, :show?
          end

          def fetch_conversation_by_display_id
            cid = params[:conversation_id]
            raise ActiveRecord::RecordNotFound, 'conversation_id required' if cid.blank?

            conversation = @voice_inbox.conversations.find_by!(display_id: cid)
            authorize conversation, :show?
            conversation
          end

          def render_call_already_accepted(error)
            render json: { error: error.message }, status: :conflict
          end

          # Only reached once the agent is on the call, or claimed it and dropped
          # it inside the window before Twilio's participant-join lands — which
          # is the no_answer case here, since nobody was ever connected.
          def finalize_call!(call)
            status = nil
            call.with_lock do
              next if call.terminal?

              status = call.in_progress? ? 'completed' : 'no_answer'
              call.update!(end_reason: 'agent_hangup')
              Custom::Voice::CallStatus::Manager.new(call: call).process_status_update(status)
            end
            Custom::Voice::CallMessageBuilder.new(call).update_status!(status: status, agent: Current.user) if status
          end

          # An agent declining a call that is still ringing hands it on instead
          # of ending it: the caller stays in the conference while the router
          # offers the turn to the next eligible agent, exactly as an unanswered
          # ring does. Their own turn closes as `rejected`, which is what counts
          # the decline against them in the reports.
          #
          # Outbound calls are created with accepted_by_agent already set, so
          # they never match — they have no ring turn to hand on.
          def declining_ringing_call?(call)
            call.incoming? && call.ringing? && call.accepted_by_agent_id.nil?
          end
        end
      end
    end
  end
end
