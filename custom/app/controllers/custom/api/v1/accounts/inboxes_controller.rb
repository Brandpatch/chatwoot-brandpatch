# frozen_string_literal: true

module Custom
  module Api
    module V1
      module Accounts
        module InboxesController
          def create_voice_channel
            unless Current.account.feature_enabled?('channel_voice') ||
                   Current.account.feature_enabled?('channel_voice_brandpatch')
              raise Pundit::NotAuthorizedError
            end

            voice_params = params.require(:channel).permit(
              :phone_number, :provider,
              provider_config: [:account_sid, :auth_token, :api_key_sid, :api_key_secret]
            )
            config = voice_params[:provider_config] || {}

            Current.account.twilio_sms.create!(
              phone_number: voice_params[:phone_number],
              account_sid: config[:account_sid],
              auth_token: config[:auth_token],
              api_key_sid: config[:api_key_sid],
              api_key_secret: config[:api_key_secret],
              medium: :sms,
              voice_enabled: true
            )
          end
        end
      end
    end
  end
end
