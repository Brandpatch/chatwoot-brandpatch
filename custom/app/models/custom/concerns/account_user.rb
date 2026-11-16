module Custom::Concerns::AccountUser
  extend ActiveSupport::Concern

  # [brandpatch] Which languages an agent speaks, for the voice IVR's
  # language routing (Custom::Voice::CallRouter, not yet built). Keeping the
  # allowed set here, next to the column it validates, rather than in the
  # router — the router reads it, it doesn't own it.
  VOICE_LANGUAGES = %w[es en].freeze

  included do
    # [brandpatch] Deliberately not named/aliased as `custom_role` — that name
    # and its backing `custom_role_id` column are read by
    # Enterprise::ConversationPolicy (see enterprise/app/policies/enterprise/conversation_policy.rb).
    # Keeping our own association and column fully separate ensures that
    # Enterprise-licensed code never activates based on data our own
    # Custom Roles feature creates.
    belongs_to :brandpatch_custom_role, optional: true, class_name: 'Custom::CustomRole',
                                         foreign_key: :brandpatch_custom_role_id, inverse_of: :account_users

    validate :brandpatch_voice_languages_are_known
  end

  private

  # Private method prefixed per custom/CLAUDE.md rule #3: this class also has
  # Enterprise::Concerns::AccountUser included on it.
  def brandpatch_voice_languages_are_known
    unknown = brandpatch_voice_languages - VOICE_LANGUAGES
    return if unknown.empty?

    errors.add(:brandpatch_voice_languages, "contiene idioma(s) no soportado(s): #{unknown.join(', ')}")
  end
end
