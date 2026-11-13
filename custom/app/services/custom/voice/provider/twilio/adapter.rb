# frozen_string_literal: true

module Custom
  module Voice
    module Provider
      module Twilio
        class Adapter
          def initialize(channel)
            @channel = channel
          end

          def initiate_call(to:, conference_sid: nil, agent_id: nil)
            call = twilio_client.calls.create(**call_params(to))

            {
              provider: 'twilio',
              call_sid: call.sid,
              status: call.status,
              call_direction: 'outbound',
              requires_agent_join: true,
              agent_id: agent_id,
              conference_sid: conference_sid
            }
          end

          # The auto-dialer's customer leg. Two differences from initiate_call:
          #
          # Every URL carries the call's placeholder SID back as dialer_sid,
          # because the row was created before Twilio had a SID to give it and
          # keeps the placeholder for life — see Custom::Call#dialer?. The
          # webhooks resolve the call from it (VoiceController#twilio_call_sid),
          # and since Twilio signs the full URL the parameter cannot be forged.
          #
          # And answering machine detection, asynchronous so the customer is put
          # through to the agent at once rather than after the seconds AMD needs
          # to decide: a human is never kept waiting, and a machine is hung up on
          # when the verdict lands (DialerCustomerLeg#record_answered_by!).
          def initiate_dialer_call(to:, dialer_sid:)
            phone_digits = @channel.phone_number.delete_prefix('+')
            url_helpers = Rails.application.routes.url_helpers

            twilio_client.calls.create(
              **call_params(to),
              url: url_helpers.custom_twilio_voice_call_url(phone: phone_digits, dialer_sid: dialer_sid),
              status_callback: url_helpers.custom_twilio_voice_status_url(phone: phone_digits, dialer_sid: dialer_sid),
              machine_detection: 'Enable',
              async_amd: 'true',
              async_amd_status_callback: url_helpers.custom_twilio_voice_amd_status_url(phone: phone_digits, dialer_sid: dialer_sid),
              async_amd_status_callback_method: 'POST'
            ).sid
          end

          private

          def call_params(to)
            phone_digits = @channel.phone_number.delete_prefix('+')

            {
              from: @channel.phone_number,
              to: to,
              url: twilio_call_twiml_url(phone_digits),
              status_callback: twilio_call_status_url(phone_digits),
              status_callback_event: %w[
                initiated ringing answered completed failed busy no-answer canceled
              ],
              status_callback_method: 'POST'
            }
          end

          def twilio_call_twiml_url(phone_digits)
            Rails.application.routes.url_helpers.custom_twilio_voice_call_url(phone: phone_digits)
          end

          def twilio_call_status_url(phone_digits)
            Rails.application.routes.url_helpers.custom_twilio_voice_status_url(phone: phone_digits)
          end

          def twilio_client
            @channel.client
          end
        end
      end
    end
  end
end
