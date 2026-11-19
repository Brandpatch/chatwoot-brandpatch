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
            params = call_params(to)
            call = twilio_client.calls.create(**params)

            {
              provider: 'twilio',
              call_sid: call.sid,
              caller_id: params[:from],
              status: call.status,
              call_direction: 'outbound',
              requires_agent_join: true,
              agent_id: agent_id,
              conference_sid: conference_sid
            }
          end

          private

          def call_params(to)
            {
              from: @channel.voice_caller_id || @channel.phone_number,
              to: to,
              url: @channel.voice_call_webhook_url,
              status_callback: @channel.voice_status_webhook_url,
              status_callback_event: %w[
                initiated ringing answered completed failed busy no-answer canceled
              ],
              status_callback_method: 'POST'
            }
          end

          def twilio_client
            @channel.client
          end
        end
      end
    end
  end
end
