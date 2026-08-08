# frozen_string_literal: true

# [brandpatch] Hooks custom SLA evaluation into the 5-minute scheduled job
# alongside the enterprise SLA trigger (which skips accounts without feature_sla?).
module Custom::TriggerScheduledItemsJob
  def perform
    super
    Custom::Sla::TriggerSlasForAccountsJob.perform_later
  end
end
