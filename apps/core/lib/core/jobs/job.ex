defmodule Core.Job do
  @moduledoc """
  Request is stored in capped collection, so document size can't change on update.
  That means all fields on update should have the same size
  """

  use Core.Schema

  @response_length 1800

  @status_pending 0
  @status_processed 1
  @status_failed 2

  def status_to_string(@status_pending), do: "pending"
  def status_to_string(@status_processed), do: "processed"
  def status_to_string(@status_failed), do: "failed"

  def status(:pending), do: @status_pending
  def status(:processed), do: @status_processed
  def status(:failed), do: @status_failed

  @primary_key :_id
  schema :jobs do
    field(:_id)
    field(:status, presence: true, inclusion: [@status_pending, @status_processed, @status_failed])
    field(:response, length: [is: @response_length])
    field(:response_size, presence: true)

    timestamps()
  end

  def encode_response(%__MODULE__{response: value} = job) do
    response = Jason.encode!(value)
    %{job | response: String.pad_trailing(response, @response_length, "."), response_size: byte_size(response)}
  end

  def encode_response(%{"response" => value} = data) do
    response = Jason.encode!(value)

    data
    |> Map.put("response", String.pad_trailing(response, @response_length, "."))
    |> Map.put("response_size", byte_size(response))
  end

  def decode_response(%__MODULE__{response: response, response_size: response_size} = job) do
    %{job | response: Jason.decode!(String.slice(response, 0, response_size))}
  end
end
