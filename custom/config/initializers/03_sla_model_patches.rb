# frozen_string_literal: true

# [brandpatch] AppliedSla is an enterprise model and does not call
# prepend_mod_with, so there is no extension point to hook: prepend it here,
# under to_prepare so the override survives a reload in development.
Rails.application.config.to_prepare do
  AppliedSla.prepend(Custom::AppliedSla)
end
