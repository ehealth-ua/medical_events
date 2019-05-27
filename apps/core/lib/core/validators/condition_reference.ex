defmodule Core.Validators.ConditionReference do
  @moduledoc false

  alias Core.Condition
  alias Core.Mongo

  def validate(value, options) do
    patient_id_hash = Keyword.get(options, :patient_id_hash)

    case Mongo.find_one(Condition.collection(), %{
           "_id" => Mongo.string_to_uuid(value),
           "patient_id" => patient_id_hash
         }) do
      nil ->
        {:error, Keyword.get(options, :message, "Condition with such id is not found")}

      _ ->
        :ok
    end
  end
end
