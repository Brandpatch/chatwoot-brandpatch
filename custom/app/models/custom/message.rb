# frozen_string_literal: true

module Custom
  module Message
    def push_event_data
      data = super
      return data unless content_type == 'voice_call'

      data.merge(custom_call: custom_call&.push_event_data)
    end
  end
end
