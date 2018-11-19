defmodule Core.Validators.ConditionReference do
  @moduledoc false

  use Vex.Validator
  alias Core.Condition
  alias Core.Mongo

  def validate(value, options) do
    patient_id_hash = Keyword.get(options, :patient_id_hash)

    case Mongo.find_one(Condition.metadata().collection, %{
           "_id" => Mongo.string_to_uuid(value),
           "patient_id" => patient_id_hash
         }) do
      nil ->
        error(options, "Condition with such id is not found")

      _ ->
        :ok
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
