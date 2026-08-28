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

          def destroy
            call = resolve_call!
            Custom::Voice::Provider::Twilio::ConferenceService.new(call: call).end_conference
            finalize_call!(call)
            call.broadcast_voice_call_event(:ended, status: call.display_status)
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

          def finalize_call!(call)
            status = nil
            call.with_lock do
              next if call.terminal?

              if call.ringing? && call.accepted_by_agent_id.nil?
                status = 'rejected'
                call.update!(end_reason: 'agent_rejected', accepted_by_agent_id: Current.user.id)
              elsif call.in_progress?
                status = 'completed'
                call.update!(end_reason: 'agent_hangup')
              else
                status = 'no_answer'
                call.update!(end_reason: 'agent_hangup')
              end
              Custom::Voice::CallStatus::Manager.new(call: call).process_status_update(status)
            end
            Custom::Voice::CallMessageBuilder.new(call).update_status!(status: status, agent: Current.user) if status
          end
        end
      end
    end
  end
end
