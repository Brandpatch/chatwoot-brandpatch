module Custom::ReportPolicy
  def view?
    @account_user.brandpatch_custom_role&.permissions&.include?('report_manage') || super
  end
end
