# frozen_string_literal: true

# [brandpatch] Extends permitted update params to allow sla_policy_id when
# custom_sla is enabled, mirroring what the enterprise module does for the
# enterprise sla flag.
module Custom::Api::V1::Accounts::ConversationsController
  def permitted_update_params
    return super unless Current.account.feature_enabled?('custom_sla')

    super.merge(params.permit(:sla_policy_id))
  end
end
