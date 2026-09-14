# frozen_string_literal: true

class CustomExceptions::CallAlreadyEnded < CustomExceptions::Base
  # Base takes the data its message interpolates; this one has nothing to fill
  # in, so the default lets it be raised by name.
  def initialize(data = {})
    super
  end

  def message
    I18n.t('errors.voice.call_already_ended')
  end

  def http_status
    409
  end
end
