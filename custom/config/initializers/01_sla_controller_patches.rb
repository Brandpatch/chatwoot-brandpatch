# frozen_string_literal: true

# [brandpatch] Patches the enterprise SLA controllers so that accounts with
# `custom_sla` enabled are treated as authorized, in addition to accounts
# with the enterprise `sla` flag. Both controllers define the same private
# `ensure_sla_feature_enabled` guard; prepending an anonymous module
# overrides it in one place without touching the enterprise source.
Rails.application.config.to_prepare do
  sla_guard = Module.new do
    def ensure_sla_feature_enabled
      return if Current.account.feature_enabled?('sla')
      return if Current.account.feature_enabled?('custom_sla')

      raise Pundit::NotAuthorizedError
    end
  end

  Api::V1::Accounts::SlaPoliciesController.prepend(sla_guard)
  Api::V1::Accounts::AppliedSlasController.prepend(sla_guard)
end
