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

    # A call is not a written reply, and this is Chatwoot's single gate for
    # "an agent answered". Leaving it open is what let the SLA read a call as
    # a response: placing one stamped first_reply_created_at and cleared
    # waiting_since, so both clocks stopped whether or not anybody picked up,
    # while answering an inbound call — which writes nothing outgoing — left
    # them running. Measured in production: 2.017 conversations counted as
    # compliant on the strength of a call alone.
    #
    # Closing it here rather than inside the SLA also keeps the reply_time and
    # first_response reporting events honest, which are fed from the same gate
    # and were telling the same story.
    def human_response?
      return false if voice_call?

      super
    end

    # Copy of ::Message#valid_first_reply? with one clause added: a call does
    # not count towards the "was there an earlier outgoing message" check.
    # Without it the override above backfires — the call message still fills
    # that count, so the agent's first real text arrives as the second outgoing
    # message and first_reply_created_at is never stamped at all, which would
    # read as nobody ever having answered.
    #
    # Kept as a copy on purpose: the count is a single query built inline
    # upstream and there is no seam to pass a filter into. Re-check this method
    # against ::Message#valid_first_reply? on every upstream sync.
    def valid_first_reply?
      return false unless human_response? && !private?
      return false if conversation.first_reply_created_at.present?

      conversation.messages.outgoing
                  .where.not(sender_type: ['AgentBot', 'Captain::Assistant'])
                  .where.not(private: true)
                  .where.not(content_type: :voice_call)
                  .where("(additional_attributes->'campaign_id') is null")
                  .count <= 1
    end

    private

    # An inbound call is not the customer writing in, so it must not open the
    # next-response clock. Answering it by phone writes nothing, so the clock
    # would then run until somebody typed: 12 of the next-response breaches
    # recorded in production were started by a call the agent had answered.
    def set_waiting_since_on_incoming_message
      return if voice_call?

      super
    end
  end
end
