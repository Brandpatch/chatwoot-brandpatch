module Custom::CsatSurveyResponsePolicy
  def index?
    @account_user.brandpatch_custom_role&.permissions&.include?('report_manage') || super
  end

  def metrics?
    @account_user.brandpatch_custom_role&.permissions&.include?('report_manage') || super
  end

  def download?
    @account_user.brandpatch_custom_role&.permissions&.include?('report_manage') || super
  end

  def update?
    @account_user.administrator? || @account_user.brandpatch_custom_role&.permissions&.include?('report_manage')
  end
end
