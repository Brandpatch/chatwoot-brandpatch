# frozen_string_literal: true

class Custom::Sla::ProcessAppliedSlaJob < ApplicationJob
  queue_as :medium

  def perform(applied_sla)
    # Re-check in case the feature was disabled after this job was enqueued.
    return unless applied_sla.account.feature_enabled?('custom_sla')

    Custom::Sla::EvaluateAppliedSlaService.new(applied_sla: applied_sla).perform
  end
end
