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
    attr_accessor :brandpatch_skip_auto_assignment, :brandpatch_silent_assignment

    # The owner following the ring turn is bookkeeping, not news. The agent is
    # already being told about the call by the call itself — the widget, the
    # ringtone and the desktop notification — and Chatwoot's assignment alert
    # says "a conversation has been assigned to you", which names a chat and not
    # a call.
    #
    # It also fires once per turn rather than once per call: 199 inbound calls
    # on 2026-09-15 took 248 turns, and every one of them mailed and pushed the
    # agent. Before the owner started following the turn the same assignment ran
    # under the agent's own click, which self_assign? discards, so none of this
    # was ever visible. See Custom::Call#assign_conversation_to!.
    #
    # Public because it is public on ::Conversation; a prepend must not narrow it.
    def notifiable_assignee_change?
      return false if brandpatch_silent_assignment

      super
    end

    private

    # A conversation resolved without a single written message left the SLA and
    # its applied_sla row was dropped — see Custom::Sla::EvaluateAppliedSlaService.
    # If the customer writes afterwards the conversation reopens and there is
    # something to measure again, but nothing would put the row back: the policy
    # is still on the conversation, so add_sla declines to act, and the row is
    # only ever created when sla_policy_id changes. 44 of 2.298 in production.
    def execute_after_update_commit_callbacks
      brandpatch_restore_applied_sla
      super
    end

    def brandpatch_restore_applied_sla
      return unless saved_change_to_status? && status == 'open'
      return if sla_policy_id.blank?
      return if applied_sla.present?

      create_applied_sla!(sla_policy_id: sla_policy_id)
    end

    def should_run_auto_assignment?
      return false if brandpatch_skip_auto_assignment

      super
    end
  end
end
