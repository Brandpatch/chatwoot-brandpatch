# frozen_string_literal: true

# [brandpatch] Entry point for the custom Voice/Twilio reimplementation.
# Prepends and route registrations are added here as each layer is built.
# See custom/app/models/custom/call.rb and custom/app/services/custom/voice/.
Rails.application.config.to_prepare do
end
