defmodule Core.Microservices.MediaStorage do
  @moduledoc false

  use Core.Microservices
  require Logger

  @behaviour Core.Behaviours.MediaStorageBehaviour
  @rpc_worker Application.get_env(:core, :rpc_worker)

  def save(id, content, bucket, resource_name) do
    headers = [{"Content-Type", MIME.from_path(resource_name)}]
    options = config()[:hackney_options]

    with {:ok, %{secret_url: url}} <- create_signed_url("PUT", bucket, resource_name, id),
         {:ok, %HTTPoison.Response{status_code: 200}} <- HTTPoison.put(url, content, headers, options) do
      :ok
    else
      :error ->
        :error

      error ->
        Logger.error("Failed to save content with error #{inspect(error)}")
        :error
    end
  end

  def create_signed_url(action, bucket, resource_name, resource_id) do
    sign_url_data = generate_sign_url_data(action, bucket, resource_name, resource_id)

    with {:ok, secret} <- @rpc_worker.run("ael_api", Ael.Rpc, :signed_url, [sign_url_data, []]) do
      {:ok, secret}
    else
      error ->
        Logger.error("Failed to create signed url with error #{inspect(error)}")
        :error
    end
  end

  defp generate_sign_url_data(action, bucket, resource_name, resource_id) do
    %{
      "action" => action,
      "bucket" => bucket,
      "resource_id" => resource_id,
      "resource_name" => resource_name
    }
    |> add_content_type(action, resource_name)
  end

  defp add_content_type(data, "GET", _resource_name), do: data

  defp add_content_type(data, _action, resource_name) do
    Map.put(data, "content_type", MIME.from_path(resource_name))
  end
end
