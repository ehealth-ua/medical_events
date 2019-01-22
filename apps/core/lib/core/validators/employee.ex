defmodule Core.Validators.Employee do
  @moduledoc false

  use Vex.Validator
  alias Core.Rpc

  @worker Application.get_env(:core, :rpc_worker)

  def validate(employee_id, options) do
    ets_key = get_key(employee_id)

    case get_data(ets_key, employee_id) do
      nil ->
        error(options, "Employee with such ID is not found")

      %{} = employee ->
        :ets.insert(:message_cache, {ets_key, employee})

        with :ok <- validate_field(:type, employee.employee_type, options),
             :ok <- validate_field(:status, employee.status, options),
             :ok <- validate_field(:legal_entity_id, employee.legal_entity_id, options) do
          :ok
        end
    end
  end

  def get_key(employee_id), do: "employee_#{employee_id}"

  def validate_field(field, remote_value, options) do
    if is_nil(Keyword.get(options, field)) or remote_value == Keyword.get(options, field) do
      :ok
    else
      error(options, Keyword.get(options, :messages)[field])
    end
  end

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end

  def get_data(ets_key, employee_id) do
    case :ets.lookup(:message_cache, ets_key) do
      [{^ets_key, employee}] -> employee
      _ -> @worker.run("ehealth", Rpc, :employee_by_id, [employee_id])
    end
  end
end
