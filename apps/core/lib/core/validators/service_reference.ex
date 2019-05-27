defmodule Core.Validators.ServiceReference do
  @moduledoc false

  alias Core.Services
  import Core.ValidationError

  @laboratory_category "laboratory"

  def validate(service_id, options) do
    case Services.get_service(service_id) do
      {:ok, %{is_active: false}} ->
        error(options, "Service should be active")

      {:ok, %{request_allowed: false}} ->
        error(options, "Request is not allowed for the service")

      {:ok, service} ->
        check_category(service, options)

      _ ->
        error(options, "Service with such ID is not found")
    end
  end

  defp check_category(%{category: nil}, _), do: :ok

  defp check_category(%{category: category}, options) do
    if !Keyword.has_key?(options, :category) or category == Keyword.get(options, :category) do
      check_observations(category, options)
    else
      error(options, "Category mismatch")
    end
  end

  defp check_observations(category, options) do
    if Keyword.has_key?(options, :observations) do
      check_observations(category, Keyword.get(options, :observations), options)
    else
      :ok
    end
  end

  defp check_observations(@laboratory_category, observations, options) do
    if is_nil(observations) or Enum.empty?(observations) do
      error(options, "Observations are mandatory when service category = #{@laboratory_category}")
    else
      :ok
    end
  end

  defp check_observations(_, _, _), do: :ok
end
