defmodule Core.Validators.Value do
  @moduledoc false

  use Vex.Validator

  def validate(value, options) do
    equals = Keyword.get(options, :equals)

    if is_nil(equals) or to_string(value) == to_string(equals) do
      :ok
    else
      error(options, "must be a #{equals}")
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
