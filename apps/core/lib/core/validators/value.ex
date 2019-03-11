defmodule Core.Validators.Value do
  @moduledoc false

  use Vex.Validator

  def validate(%BSON.Binary{} = value, options) do
    value
    |> to_string()
    |> validate(options)
  end

  def validate(value, options) do
    equals = Keyword.get(options, :equals)

    if is_nil(equals) or value == equals do
      :ok
    else
      error(options, "must be a #{equals}")
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
