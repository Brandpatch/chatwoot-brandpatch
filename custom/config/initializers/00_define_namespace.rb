# frozen_string_literal: true

# [brandpatch] Explicitly defines the `Custom` top-level namespace so it
# exists even before any feature-specific file is added under custom/app/**.
#
# Without this, Object.const_defined?(:Custom, false) stays false until
# Zeitwerk can associate a real .rb file with the namespace, which breaks
# config/initializers/01_inject_enterprise_edition_module.rb#each_extension_for
# for every class in the app that calls prepend_mod/include_mod_with/
# extend_mod_with (not just our own) — that method isn't guarded for a
# `false` (vs. `nil`) extension namespace.
#
# Zeitwerk recognizes this as an explicit namespace: once custom/app/models/
# custom/custom_role.rb (etc.) is added, Zeitwerk reopens this same module
# instead of conflicting with it.
module Custom; end
