# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        # The auto-dialer's API, for the lead system that feeds it: ask for a
        # call to a lead (create), and read back how the calls went (index).
        #
        # Administrators only, and both behind auto_dialer_brandpatch: with the
        # flag off the endpoints do not exist as far as the caller can tell.
        class DialerCallsController < ::Api::V1::Accounts::BaseController
          E164 = /\A\+[1-9]\d{6,14}\z/
          PER_PAGE = 100

          before_action :check_admin_authorization?
          before_action :ensure_dialer_enabled!

          rescue_from Custom::Voice::CallRouter::DialerUnavailable do |error|
            render json: { error: error.message }, status: :conflict
          end

          # Polled by the lead system with the updated_at of the last row it
          # saw, so a call shows up again every time its outcome moves.
          def index
            since = updated_since
            return render_unprocessable('updated_since is invalid') if params[:updated_since].present? && since.nil?

            @calls = Custom::Call.where(account_id: Current.account.id)
                                 .where("calls.meta -> 'dialer' IS NOT NULL")
                                 .includes(:contact, :conversation, :accepted_by_agent)
                                 .order(:updated_at, :id)
                                 .page(params[:page]).per(PER_PAGE)
            @calls = @calls.where(updated_at: since..) if since
          end

          def create
            return render_unprocessable('phone_number must be E.164') unless E164.match?(params[:phone_number].to_s)
            return render_unprocessable('external_id is required') if params[:external_id].blank?

            call = dialer_call_builder.perform!

            render json: { call_id: call.id, conversation_id: call.conversation.display_id,
                           agent_id: call.accepted_by_agent_id, external_id: call.dialer['external_id'] }, status: :created
          end

          private

          def dialer_call_builder
            Custom::Voice::DialerCallBuilder.new(
              inbox: voice_inbox, requester: Current.user, phone_number: params[:phone_number], external_id: params[:external_id].to_s,
              name: params[:name], note: params[:note], metadata: params.permit(metadata: {})[:metadata].to_h
            )
          end

          def ensure_dialer_enabled!
            raise ActiveRecord::RecordNotFound unless Current.account.feature_enabled?('auto_dialer_brandpatch')
          end

          def voice_inbox
            inbox = Current.account.inboxes.find(params[:inbox_id])
            raise ActiveRecord::RecordNotFound unless inbox.channel_type == 'Channel::TwilioSms' && inbox.channel.voice_enabled?

            inbox
          end

          # Epoch seconds or ISO 8601, whichever the caller has at hand.
          def updated_since
            value = params[:updated_since].to_s
            return if value.blank?

            value.match?(/\A\d+\z/) ? Time.zone.at(value.to_i) : Time.zone.iso8601(value)
          rescue ArgumentError
            nil
          end

          def render_unprocessable(message)
            render json: { error: message }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
