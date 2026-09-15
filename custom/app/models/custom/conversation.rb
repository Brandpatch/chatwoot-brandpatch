# frozen_string_literal: true

module Custom
  module Conversation
    # A conversation opened by an inbound call has no owner yet, and Chatwoot's
    # auto-assignment does not know that. It stamps one the moment the record is
    # created — round robin over whoever is online, with no notion of being on a
    # call — so it picks agents the voice router has deliberately skipped: one
    # already talking, or one it will never ring. The two choose by different
    # rules and never speak to each other.
    #
    # When an agent answers, assign_conversation_to! corrects the owner. When
    # nobody answers, nothing does, and the conversation keeps an owner who
    # never had contact with the customer. A later call from that customer lands
    # in the same conversation and is offered to that owner first, which is what
    # agents report as receiving calls for chats that belong to someone else.
    # Measured in one afternoon in production: 23 conversations.
    #
    # Skipping the stamp leaves the conversation unassigned until somebody
    # actually takes the call, which is also the honest state: nobody has.
    attr_accessor :brandpatch_skip_auto_assignment

    private

    def should_run_auto_assignment?
      return false if brandpatch_skip_auto_assignment

      super
    end
  end
end
