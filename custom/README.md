# custom/

BrandPatch's own extensions to Chatwoot, built independently from
`enterprise/` (which remains untouched and unused).

This directory is loaded by Rails the same way `enterprise/` is
(see `config/application.rb`), and its `Custom::` namespaced classes are
auto-discovered by the same `include_mod_with`/`prepend_mod_with` hooks
used for `Enterprise::` modules (see `ChatwootApp.extensions` in
`lib/chatwoot_app.rb`).

Do not add code here that depends on classes under `enterprise/`.
