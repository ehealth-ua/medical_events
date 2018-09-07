defmodule Core.Validators.StrictPresence do
  @moduledoc false

  use Vex.Validator
  alias Vex.Validators.Presence

  def validate(false, _options), do: :ok
  def validate(value, options), do: Presence.validate(value, options)
end
