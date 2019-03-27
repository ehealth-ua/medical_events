defmodule Core.Validators.ServiceRequestReference do
  @moduledoc false

  use Vex.Validator
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Validators.Employee

  @status_active ServiceRequest.status(:active)
  @status_in_progress ServiceRequest.status(:in_progress)

  @counselling_category ServiceRequest.category(:counselling)

  def validate(value, options) do
    case ServiceRequests.get_by_id(value) do
      nil ->
        error(options, "Service request with such id is not found")

      {:ok,
       %ServiceRequest{
         status: status,
         used_by_employee: used_by_employee,
         used_by_legal_entity: used_by_legal_entity,
         expiration_date: expiration_date,
         category: category
       }} ->
        with :ok <- validate_status(status, options),
             :ok <- validate_used_by_employee(used_by_employee, options),
             :ok <- validate_used_by_legal_entity(used_by_legal_entity, options),
             :ok <- validate_expiration_date(expiration_date, options),
             :ok <- validate_category(category, options) do
          :ok
        end

      _ ->
        error(options, "Unknown validation error")
    end
  end

  defp validate_status(@status_active, _), do: :ok
  defp validate_status(@status_in_progress, _), do: :ok
  defp validate_status(_, options), do: error(options, "Service request is not active or in progress")

  defp validate_used_by_employee(nil, _), do: :ok

  defp validate_used_by_employee(used_by_employee, options) do
    id = used_by_employee.identifier.value
    client_id = Keyword.get(options, :client_id)
    ets_key = Employee.get_key(id)

    case Employee.get_data(ets_key, id) do
      nil ->
        error(options, "Service request must be related to the same legal entity")

      %{} = employee ->
        :ets.insert(:message_cache, {ets_key, employee})

        if employee.legal_entity_id == client_id do
          :ok
        else
          error(options, "Service request must be related to the same legal entity")
        end
    end
  end

  defp validate_used_by_legal_entity(nil, options), do: error(options, "Service request must be used")

  defp validate_used_by_legal_entity(used_by_legal_entity, options) do
    id = used_by_legal_entity.identifier.value
    client_id = Keyword.get(options, :client_id)
    legal_entity_id = UUID.binary_to_string!(id.binary)

    if legal_entity_id == client_id do
      :ok
    else
      error(options, "Service request is used by another legal_entity")
    end
  end

  defp validate_expiration_date(nil, _), do: :ok

  defp validate_expiration_date(expiration_date, options) do
    datetime = Keyword.get(options, :datetime)

    case DateTime.compare(expiration_date, datetime) do
      :lt -> error(options, "Service request expiration date must be a datetime greater than or equal")
      _ -> :ok
    end
  end

  defp validate_category(nil, options), do: error(options, "Incorect service request type")
  defp validate_category(@counselling_category, _), do: :ok

  defp validate_category(category, options) when is_map(category),
    do: validate_category(category.coding |> List.first() |> Map.get(:code), options)

  defp validate_category(_, options), do: validate_category(nil, options)

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end
end
