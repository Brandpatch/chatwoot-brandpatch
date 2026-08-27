# frozen_string_literal: true

module Custom
  module Voice
    module Provider
      module Twilio
        class RecordingAttachmentJob < ApplicationJob
          queue_as :low

          retry_on Down::Error, wait: 5.seconds, attempts: 3

          def perform(call_id, recording_sid, recording_url, recording_duration = nil)
            call = Custom::Call.find_by(id: call_id)
            return if call.blank?

            Custom::Voice::Provider::Twilio::RecordingAttachmentService.new(
              call: call,
              recording_sid: recording_sid,
              recording_url: recording_url,
              recording_duration: recording_duration
            ).perform
          end
        end
      end
    end
  end
end
