module Custom::ArticlePolicy
  def index?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def update?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def show?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def edit?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def create?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def destroy?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end

  def reorder?
    @account_user.brandpatch_custom_role&.permissions&.include?('knowledge_base_manage') || super
  end
end
