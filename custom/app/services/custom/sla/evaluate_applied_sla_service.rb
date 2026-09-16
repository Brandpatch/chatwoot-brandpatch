# frozen_string_literal: true

class Custom::Sla::EvaluateAppliedSlaService
  pattr_initialize [:applied_sla!]

  def perform
    return unless conversation.sla_applicable?
    return handle_unmeasurable if applied_sla.brandpatch_clock_started_at.nil?

    check_frt
    check_nrt
    check_rt

    return unless conversation.resolved?

    handle_hit_sla
  end

  private

  delegate :conversation, :sla_policy, to: :applied_sla

  # Nothing was written, so there is nothing to measure. Returning early is
  # also what keeps a nil deadline out of within_threshold?, which would raise
  # on the comparison: the three clocks can only be nil for want of a start.
  #
  # Once the conversation is resolved no text is coming, and the row cannot
  # stay behind: the report's denominator is every applied_sla in the range
  # whatever its status, so an untouched one counts as compliant — 2.042 of the
  # 2.253 call-only conversations in production are sitting on a 'hit' today
  # for exactly that reason. Dropping the row takes the conversation out of
  # both sides of the ratio, which is what "calls do not count" has to mean.
  #
  # The policy stays on the conversation because Chatwoot forbids removing it
  # (Enterprise::Concerns::Conversation#validate_sla_policy). Custom::Conversation
  # puts the row back if the customer writes later and reopens it.
  def handle_unmeasurable
    applied_sla.destroy! if conversation.resolved?
  end

  def check_frt
    return if sla_policy.first_response_time_threshold.blank?
    return if frt_was_hit?
    return if within_threshold?(applied_sla.frt_due_at)

    handle_missed_sla('frt')
  end

  def check_nrt
    return if sla_policy.next_response_time_threshold.blank?
    return if conversation.first_reply_created_at.blank?
    return if conversation.waiting_since.blank?
    return if within_threshold?(applied_sla.nrt_due_at)

    handle_missed_sla('nrt')
  end

  def check_rt
    return if sla_policy.resolution_time_threshold.blank?
    return if conversation.resolved?
    return if within_threshold?(applied_sla.rt_due_at)

    handle_missed_sla('rt')
  end

  def within_threshold?(due_at)
    Time.zone.now.to_i < due_at
  end

  def frt_was_hit?
    return false if applied_sla.frt_due_at.blank?
    return false if conversation.first_reply_created_at.blank?

    conversation.first_reply_created_at.to_i <= applied_sla.frt_due_at
  end

  def handle_missed_sla(type)
    meta = type == 'nrt' ? { message_id: last_incoming_message_id } : {}
    return if already_missed?(type, meta)

    create_sla_event(type, meta)
    log_miss(type)
    applied_sla.update!(sla_status: 'active_with_misses') unless applied_sla.active_with_misses?
  end

  def handle_hit_sla
    if applied_sla.active?
      applied_sla.update!(sla_status: 'hit')
      log_result('hit')
    else
      applied_sla.update!(sla_status: 'missed')
      log_result('missed')
    end
  end

  def already_missed?(type, meta)
    SlaEvent.exists?(applied_sla: applied_sla, event_type: type, meta: meta)
  end

  def last_incoming_message_id
    Message.where(account_id: conversation.account_id, conversation_id: conversation.id, message_type: :incoming).last&.id
  end

  def create_sla_event(event_type, meta)
    SlaEvent.create!(
      applied_sla: applied_sla,
      conversation: conversation,
      event_type: event_type,
      meta: meta,
      account: applied_sla.account,
      inbox: conversation.inbox,
      sla_policy: sla_policy
    )
  end

  def log_miss(type)
    Rails.logger.warn "Custom SLA #{type} missed for conversation #{conversation.id} " \
                      "in account #{applied_sla.account_id} for sla_policy #{sla_policy.id}"
  end

  def log_result(result)
    Rails.logger.info "Custom SLA #{result} for conversation #{conversation.id} " \
                      "in account #{applied_sla.account_id} for sla_policy #{sla_policy.id}"
  end
end
