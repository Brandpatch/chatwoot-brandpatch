# frozen_string_literal: true

class Custom::Sla::TriggerSlasForAccountsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.joins(:sla_policies).distinct.find_each do |account|
      next unless account.feature_enabled?('custom_sla')

      Rails.logger.info "Enqueuing Custom::Sla::ProcessAccountAppliedSlasJob for account #{account.id}"
      Custom::Sla::ProcessAccountAppliedSlasJob.perform_later(account)
    end
  end
end
