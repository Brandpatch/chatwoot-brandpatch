module Custom::Api::V1::Accounts::AgentsController
  def create
    super
    return if @agent.blank?

    associate_agent_with_brandpatch_custom_role
    associate_agent_with_brandpatch_voice_languages
  end

  def update
    super
    associate_agent_with_brandpatch_custom_role
    associate_agent_with_brandpatch_voice_languages
  end

  private

  def associate_agent_with_brandpatch_custom_role
    return if params[:brandpatch_custom_role_id].present? && !Current.account.feature_enabled?('custom_roles_brandpatch')

    @agent.current_account_user.update!(brandpatch_custom_role_id: params[:brandpatch_custom_role_id])
  end

  # [brandpatch] Read by Custom::Voice::CallRouter to prefer agents who speak
  # the caller's chosen language. `nil` means the request didn't touch this
  # field at all (e.g. a plain role/availability update); an explicit `[]`
  # clears it.
  def associate_agent_with_brandpatch_voice_languages
    return if params[:brandpatch_voice_languages].nil?

    @agent.current_account_user.update!(brandpatch_voice_languages: params[:brandpatch_voice_languages])
  end
end
