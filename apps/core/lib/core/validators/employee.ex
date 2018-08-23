defmodule Core.Validators.Employee do
  @moduledoc false

  use Vex.Validator
  alias Core.Headers

  @il_microservice Application.get_env(:core, :microservices)[:il]

  def validate(employee_id, options) do
    headers = [{String.to_atom(Headers.consumer_metadata()), Keyword.get(options, :legal_entity_id)}]

    case @il_microservice.get_employee(employee_id, headers) do
      {:ok, %{"data" => employee}} ->
        with :ok <- validate_field(:type, employee, options),
             :ok <- validate_field(:status, employee, options),
             :ok <- validate_field(:legal_entity_id, employee, options) do
          :ok
        end

      _ ->
        error(options, "Employee with such ID is not found")
    end
  end

  def validate_field(field, employee, options) do
    if is_nil(Keyword.get(options, field)) or employee[to_string(field)] == Keyword.get(options, field) do
      :ok
    else
      error(options, Keyword.get(options, :messages)[field])
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
