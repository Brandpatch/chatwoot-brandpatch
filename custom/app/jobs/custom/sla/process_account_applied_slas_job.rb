# frozen_string_literal: true

class Custom::Sla::ProcessAccountAppliedSlasJob < ApplicationJob
  queue_as :medium

  def perform(account)
    return unless account.feature_enabled?('custom_sla')

    account.applied_slas.with_sla_applicable_conversation.where(sla_status: %w[active active_with_misses]).each do |applied_sla|
      Custom::Sla::ProcessAppliedSlaJob.perform_later(applied_sla)
    end
  end
end
