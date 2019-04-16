defmodule Core.Validators.ServiceReference do
  @moduledoc false

  use Vex.Validator

  @worker Application.get_env(:core, :rpc_worker)

  def validate(service_id, options) do
    category = Keyword.get(options, :category)

    case @worker.run("ehealth", EHealth.Rpc, :service_by_id, [to_string(service_id)]) do
      {:ok, service} ->
        check_category(service, category, options)

      _ ->
        {:error, message(options, "Service with such ID is not found")}
    end
  end

  defp check_category(%{category: nil}, _, _), do: :ok

  defp check_category(%{category: category}, service_request_category, options) do
    if category == service_request_category do
      :ok
    else
      {:error, message(options, "Category mismatch")}
    end
  end
end
