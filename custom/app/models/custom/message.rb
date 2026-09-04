# frozen_string_literal: true

module Custom
  module Message
    # Both the core message partial and Enterprise::Message#push_event_data
    # serialize `message.call`, which Enterprise points at its own Call model
    # over the shared `calls` table. ActiveStorage keys attachments by class
    # name, so a recording our service attached to Custom::Call is invisible
    # from there: the payload ships recording_url: nil and the conversation
    # bubble never renders the player. Resolving the reader to our own record
    # fixes both transports at once, and carries the fields Enterprise's
    # push_event_data has no notion of, current_ring_agent_id among them.
    def call
      custom_call
    end
  end
end
