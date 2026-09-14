# frozen_string_literal: true

module Custom
  class CallFinder
    RESULTS_PER_PAGE = 25

    def initialize(current_user, current_account, params)
      @current_user = current_user
      @current_account = current_account
      @params = params
    end

    def perform
      @calls = @current_account.custom_calls
      filter_by_visibility
      filter_by_status
      filter_by_attendance
      filter_by_direction
      filter_by_inbox
      filter_by_agent
      filter_by_date_range

      { calls: paginated_calls, count: @calls.count }
    end

    private

    # Everyone else only ever sees their own calls, and only within the
    # conversations they are allowed to read.
    def filter_by_visibility
      return if account_wide_access?

      @calls = belonging_to(@calls, @current_user.id).where(conversation_id: accessible_conversations)
    end

    # A call is an agent's own if they took it, or if they were given a turn,
    # lost it, and nobody else ended up taking it either.
    #
    # The second half is what makes their own missed calls reachable at all: a
    # call nobody answered carries no accepted_by_agent_id, so reading that
    # column alone left the Missed tab unable to return a single row.
    #
    # It is also why the second half has to exclude the calls somebody
    # answered. Declining does not end a call — the router passes it to the
    # next agent, who often answers — so a turn the agent lost is not proof the
    # call stayed unanswered. Without that exclusion the list handed them a
    # call another agent took, with its recording and its conversation, over a
    # row reading "answered by" somebody else.
    def belonging_to(scope, agent_id)
      scope.where(
        "calls.accepted_by_agent_id = :agent_id OR (calls.id IN (:missed) AND NOT (#{Custom::Call::ANSWERED_SQL}))",
        agent_id: agent_id,
        missed: missed_turn_call_ids(agent_id)
      )
    end

    def missed_turn_call_ids(agent_id)
      Custom::CallRingAttempt.where(
        agent_id: agent_id,
        outcome: Custom::CallRingAttempt::MISSED_OUTCOMES
      ).select(:call_id)
    end

    def accessible_conversations
      ::Conversations::PermissionFilterService.new(
        @current_account.conversations, @current_user, @current_account
      ).perform.select(:id)
    end

    def account_wide_access?
      account_user = Current.account_user
      account_user&.administrator? ||
        account_user&.brandpatch_custom_role&.permissions&.include?('report_manage')
    end

    def filter_by_status
      @calls = @calls.where(status: Custom::Call.status_from_display(@params[:status])) if @params[:status].present?
    end

    # Whether an agent was on the call is not a status: a caller who hangs up
    # while it rings lands on 'completed' with nobody on it. Only terminal calls
    # can be judged, since a ringing one has not failed to be attended yet.
    # Shares Custom::Call's definition so this list and the reports agree.
    def filter_by_attendance
      return if @params[:attended].blank?

      @calls = @calls.where(status: Custom::Call::TERMINAL_STATUSES)
      @calls = ActiveModel::Type::Boolean.new.cast(@params[:attended]) ? @calls.answered : @calls.unanswered
    end

    def filter_by_direction
      @calls = @calls.where(direction: Custom::Call.direction_from_label(@params[:direction])) if @params[:direction].present?
    end

    def filter_by_inbox
      @calls = @calls.where(inbox_id: @params[:inbox_id]) if @params[:inbox_id].present?
    end

    # Same definition as visibility, so filtering by an agent answers the same
    # question the figures above the list do. Reading accepted_by_agent_id
    # alone here undid filter_by_visibility for the agent themselves, since the
    # page always sends their own id: their missed calls made it past the
    # visibility check and were dropped again one line later.
    def filter_by_agent
      @calls = belonging_to(@calls, @params[:agent_id]) if @params[:agent_id].present?
    end

    def filter_by_date_range
      return if @params[:since].blank? || @params[:until].blank?

      @calls = @calls.where(created_at: Time.zone.at(@params[:since].to_i)..Time.zone.at(@params[:until].to_i))
    end

    def paginated_calls
      @calls.includes(:contact, :conversation, :accepted_by_agent, inbox: :channel)
            .order(created_at: :desc)
            .page(@params[:page] || 1)
            .per(RESULTS_PER_PAGE)
    end
  end
end
