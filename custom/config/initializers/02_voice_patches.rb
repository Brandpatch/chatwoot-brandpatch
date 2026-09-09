# frozen_string_literal: true

# [brandpatch] Entry point for the custom Voice/Twilio reimplementation.
# Model extensions (Custom::Concerns::*, Custom::Message, Custom::Channel::TwilioSms)
# are picked up automatically via ChatwootApp.extensions + prepend_mod_with/include_mod_with.
# Route registrations are added here in T8.
Rails.application.config.to_prepare do
end
