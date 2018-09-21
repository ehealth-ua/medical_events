defmodule Core.Validators.MongoUUID do
  @moduledoc false

  use Vex.Validator
  alias Core.Mongo

  def validate(%BSON.Binary{subtype: :uuid}, _), do: :ok

  def validate(value, options) when is_binary(value) do
    case Mongo.string_to_uuid(value) do
      nil -> error(options, "must be a valid UUID string")
      _ -> :ok
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
