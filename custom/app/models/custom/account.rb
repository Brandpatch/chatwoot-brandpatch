# [brandpatch] Account-wide pause for inbound calling.
#
# Customer service stops taking calls during their weekly meeting. Until now
# they did it by unassigning every agent from every inbox: 544 agent-inbox pairs
# across 15 inboxes, 5 to 10 minutes of clicking. Worse, voice rides on the SMS
# inboxes — `Compinche` carried 122.927 messages alongside 37.505 calls over 30
# days — so unassigning took the team off messaging too, which is the one thing
# they asked to keep.
#
# Availability cannot express this either: it is a single per-account status
# shared by calls and conversation auto-assignment, so going offline silences
# both. The pause therefore belongs to the voice channel, not to the agent and
# not to the inbox, and it is read by Custom::Voice::CallRouter alone.
#
# Stored as the instant it started rather than a boolean so the UI can say since
# when. A single switch is much easier to forget than 544 clicks were, and the
# only cheap defence against a pause nobody lifted is making its age visible.
#
# Prefixed, like every name this fork adds: Enterprise::Account is prepended
# onto the same class, and a shared name is what silently runs licensed code.
module Custom::Account
  BRANDPATCH_INBOUND_CALLS_PAUSED_AT = 'brandpatch_inbound_calls_paused_at'

  def brandpatch_inbound_calls_paused?
    brandpatch_inbound_calls_paused_at.present?
  end

  def brandpatch_inbound_calls_paused_at
    epoch = settings.to_h[BRANDPATCH_INBOUND_CALLS_PAUSED_AT]
    epoch.present? ? Time.zone.at(epoch.to_i) : nil
  end

  # Re-pausing keeps the original instant: "paused since" is only worth showing
  # if a second click cannot quietly reset it back to nothing.
  def brandpatch_pause_inbound_calls!
    return if brandpatch_inbound_calls_paused?

    update!(settings: settings.to_h.merge(BRANDPATCH_INBOUND_CALLS_PAUSED_AT => Time.zone.now.to_i))
  end

  def brandpatch_resume_inbound_calls!
    return unless brandpatch_inbound_calls_paused?

    update!(settings: settings.to_h.except(BRANDPATCH_INBOUND_CALLS_PAUSED_AT))
  end
end
