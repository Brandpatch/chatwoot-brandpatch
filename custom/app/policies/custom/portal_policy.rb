module Custom::PortalPolicy
  def update?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def edit?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def logo?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end
end
