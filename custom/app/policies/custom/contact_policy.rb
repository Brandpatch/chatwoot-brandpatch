module Custom::ContactPolicy
  def export?
    @account_user.brandpatch_custom_role&.permissions&.include?('contact_manage') || super
  end

  def import?
    @account_user.brandpatch_custom_role&.permissions&.include?('contact_manage') || super
  end
end
