defmodule Core.Validators.Division do
  @moduledoc false

  use Vex.Validator
  alias Core.Headers

  @il_microservice Application.get_env(:core, :microservices)[:il]

  def validate(division_id, options) do
    headers = [
      {String.to_atom(Headers.consumer_metadata()),
       Jason.encode!(%{"client_id" => Keyword.get(options, :legal_entity_id)})}
    ]

    case @il_microservice.get_division(division_id, headers) do
      {:ok, %{"data" => division}} ->
        with :ok <- validate_field({:status, ["status"]}, division, options),
             :ok <- validate_field({:legal_entity_id, ["legal_entity_id"]}, division, options) do
          :ok
        end

      _ ->
        error(options, "Division with such ID is not found")
    end
  end

  def validate_field({field, remote_field}, division, options) do
    if is_nil(Keyword.get(options, field)) or get_in(division, remote_field) == Keyword.get(options, field) do
      :ok
    else
      error(options, Keyword.get(options, :messages)[field])
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
