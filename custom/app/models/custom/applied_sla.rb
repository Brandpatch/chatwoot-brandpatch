# frozen_string_literal: true

module Custom
  # Chatwoot starts the first-response and resolution clocks at
  # conversation.created_at, not at any message. On a conversation opened by a
  # call that means the deadline is already running before a single word exists:
  # the first text arrives 99 s later in the median and past the five-minute
  # threshold in 20,5 % of cases, so the conversation was losing the SLA for
  # time nobody could have answered in.
  #
  # Both clocks now start at the first message either side actually wrote. On a
  # conversation without calls this is a no-op — the gap between creating one
  # and its first message is 0 s in the median and 1 s at the most, measured
  # over 3.000 of them.
  module AppliedSla
    def frt_due_at(working_hours_by_day_cache: nil)
      return nil if brandpatch_clock_started_at.nil?
      return nil if sla_policy.first_response_time_threshold.blank?

      calculate_due_at(brandpatch_clock_started_at, sla_policy.first_response_time_threshold,
                       working_hours_by_day_cache: working_hours_by_day_cache)
    end

    def rt_due_at(working_hours_by_day_cache: nil)
      return nil if brandpatch_clock_started_at.nil?
      return nil if sla_policy.resolution_time_threshold.blank?

      calculate_due_at(brandpatch_clock_started_at, sla_policy.resolution_time_threshold,
                       working_hours_by_day_cache: working_hours_by_day_cache)
    end

    # waiting_since already ignores calls, from Custom::Message. The gate here
    # is for the screen: a conversation that never held text has no SLA, and
    # showing it a next-response deadline would contradict that.
    def nrt_due_at(working_hours_by_day_cache: nil)
      return nil if brandpatch_clock_started_at.nil?

      super
    end

    # Nil while nothing has been written. Activity messages are excluded —
    # "assigned to X", "resolved by Y" are not somebody talking, and counting
    # them is what made an earlier reading of this claim that 96 % of the
    # conversations with calls also had text when the real figure is 42 %.
    # Private notes are excluded too: an internal note is not a reply.
    #
    # Memoized because every serialization of a conversation derives the three
    # deadlines, and this is the only one of them that costs a query.
    def brandpatch_clock_started_at
      return @brandpatch_clock_started_at if defined?(@brandpatch_clock_started_at)

      @brandpatch_clock_started_at = conversation.messages
                                                 .where(message_type: %i[incoming outgoing], private: false)
                                                 .where.not(content_type: :voice_call)
                                                 .reorder(nil)
                                                 .minimum(:created_at)
    end
  end
end
