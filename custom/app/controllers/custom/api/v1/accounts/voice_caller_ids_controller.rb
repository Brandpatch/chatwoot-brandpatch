# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        # The numbers a voice inbox can call out with, read from its own Twilio
        # account: the inbox's number first, then the numbers verified there as
        # caller IDs. It is what the inbox settings offer in place of a free-text
        # field, because a number Twilio has not verified is refused at the
        # moment of dialling.
        #
        # Administrators only, since the list is the inbox's Twilio account as
        # far as it can be seen with the inbox's own credentials.
        class VoiceCallerIdsController < ::Api::V1::Accounts::BaseController
          before_action :check_admin_authorization?
          before_action :set_voice_channel

          def index
            render json: { payload: @channel.available_voice_caller_ids }
          rescue ::Twilio::REST::RestError => e
            # Said out loud on purpose: an empty list would read as "nothing is
            # verified" and send whoever is configuring the inbox looking in
            # the wrong place.
            render json: { error: e.message }, status: :bad_gateway
          end

          private

          # Answered before any call to Twilio: an inbox that is not a voice
          # inbox has no account to ask.
          def set_voice_channel
            @channel = Current.account.inboxes.find(params[:inbox_id]).channel
            return if @channel.is_a?(::Channel::TwilioSms) && @channel.voice_enabled?

            render json: { error: 'The inbox is not a voice inbox' }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
