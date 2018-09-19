defmodule Core.Validators.Employee do
  @moduledoc false

  use Vex.Validator
  alias Core.Headers

  @il_microservice Application.get_env(:core, :microservices)[:il]

  def validate(employee_id, options) do
    headers = [
      {String.to_atom(Headers.consumer_metadata()),
       Jason.encode!(%{"client_id" => Keyword.get(options, :legal_entity_id)})}
    ]

    ets_key = "employee_#{employee_id}"

    case get_data(ets_key, employee_id, headers) do
      {:ok, %{"data" => employee}} ->
        :ets.insert(:message_cache, {ets_key, employee})

        with :ok <- validate_field({:type, ["employee_type"]}, employee, options),
             :ok <- validate_field({:status, ["status"]}, employee, options),
             :ok <- validate_field({:legal_entity_id, ["legal_entity", "id"]}, employee, options) do
          :ok
        end

      _ ->
        error(options, "Employee with such ID is not found")
    end
  end

  def validate_field({field, remote_field}, employee, options) do
    if is_nil(Keyword.get(options, field)) or get_in(employee, remote_field) == Keyword.get(options, field) do
      :ok
    else
      error(options, Keyword.get(options, :messages)[field])
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end

  defp get_data(ets_key, employee_id, headers) do
    case :ets.lookup(:message_cache, ets_key) do
      [{^ets_key, employee}] -> {:ok, %{"data" => employee}}
      _ -> @il_microservice.get_employee(employee_id, headers)
    end
  end
end
