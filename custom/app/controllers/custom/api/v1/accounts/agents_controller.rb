module Custom::Api::V1::Accounts::AgentsController
  def create
    super
    return if @agent.blank?

    associate_agent_with_brandpatch_custom_role
  end

  def update
    super
    associate_agent_with_brandpatch_custom_role
  end

  private

  def associate_agent_with_brandpatch_custom_role
    return if params[:brandpatch_custom_role_id].present? && !Current.account.feature_enabled?('custom_roles_brandpatch')

    @agent.current_account_user.update!(brandpatch_custom_role_id: params[:brandpatch_custom_role_id])
  end
end
