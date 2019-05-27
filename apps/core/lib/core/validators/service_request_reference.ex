defmodule Core.Validators.ServiceRequestReference do
  @moduledoc false

  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Services
  alias Core.Validators.Employee
  import Core.ValidationError

  @status_active ServiceRequest.status(:active)
  @status_in_progress ServiceRequest.status(:in_progress)

  @counselling_category ServiceRequest.category(:counselling)

  @worker Application.get_env(:core, :rpc_worker)

  def validate(value, options) do
    service_id = Keyword.get(options, :service_id)

    case ServiceRequests.get_by_id(value) do
      nil ->
        error(options, "Service request with such id is not found")

      {:ok,
       %ServiceRequest{
         status: status,
         used_by_employee: used_by_employee,
         used_by_legal_entity: used_by_legal_entity,
         expiration_date: expiration_date,
         category: category,
         code: code
       }} ->
        with :ok <- validate_status(status, options),
             :ok <- validate_used_by_employee(used_by_employee, options),
             :ok <- validate_used_by_legal_entity(used_by_legal_entity, options),
             :ok <- validate_expiration_date(expiration_date, options),
             :ok <- validate_category(category, code, service_id, options),
             :ok <- validate_code(code, service_id, options) do
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

    if id == client_id do
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

  defp validate_category(category, _, nil, options) do
    category_value = category.coding |> List.first() |> Map.get(:code)

    if category_value == @counselling_category do
      :ok
    else
      error(options, "Incorect service request type")
    end
  end

  defp validate_category(category, code, service_id, options) do
    category_value = category.coding |> List.first() |> Map.get(:code)
    reference_type = if !is_nil(code), do: code.identifier.type.coding |> List.first() |> Map.get(:code)

    with {:ok, %{category: service_category}} <- Services.get_service(service_id) do
      if reference_type == "service_group" and service_category != category_value do
        error(options, "Service request category should be equal to service category")
      else
        :ok
      end
    else
      _ -> :ok
    end
  end

  defp validate_code(_, nil, _), do: :ok

  defp validate_code(nil, _, _), do: :ok

  defp validate_code(code, service_id, options) do
    reference_type = code.identifier.type.coding |> List.first() |> Map.get(:code)

    case reference_type do
      "service" ->
        if service_id == to_string(code.identifier.value) do
          :ok
        else
          error(options, "Should reference the same service that is referenced in diagnostic report")
        end

      "service_group" ->
        validate_service_belongs_to_group(service_id, code.identifier.value, options)
    end
  end

  defp validate_service_belongs_to_group(service_id, service_group_id, options) do
    case @worker.run("ehealth", EHealth.Rpc, :service_belongs_to_group?, [
           to_string(service_id),
           to_string(service_group_id)
         ]) do
      true ->
        :ok

      false ->
        error(options, "Service referenced in diagnostic report should belong to service group")

      _ ->
        error(options, "Rpc error")
    end
  end
end
