defmodule Core.Microservices.MediaStorage do
  @moduledoc false

  use Core.Microservices
  require Logger

  @behaviour Core.Behaviours.MediaStorageBehaviour

  def save(id, content, bucket, resource_name) do
    headers = [{"Content-Type", MIME.from_path(resource_name)}]
    options = config()[:hackney_options]

    with {:ok, %{"data" => %{"secret_url" => url}}} <- create_signed_url("PUT", bucket, resource_name, id),
         {:ok, %HTTPoison.Response{status_code: 200}} <- HTTPoison.put(url, content, headers, options) do
      :ok
    end
  end

  def create_signed_url(action, bucket, resource_name, resource_id) do
    data =
      %{
        "action" => action,
        "bucket" => bucket,
        "resource_id" => resource_id,
        "resource_name" => resource_name
      }
      |> Map.put("content_type", MIME.from_path(resource_name))

    post("/media_content_storage_secrets", Jason.encode!(%{"secret" => data}), [])
  end
end
