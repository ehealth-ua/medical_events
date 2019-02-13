defmodule Core.Job do
  @moduledoc """
  Request is stored in capped collection, so document size can't change on update.
  That means all fields on update should have the same size
  """

  use Core.Schema

  @response_length 10_000

  @status_pending 0
  @status_processed 1
  @status_failed 2
  @status_failed_with_error 3

  def status_to_string(@status_pending), do: "pending"
  def status_to_string(@status_processed), do: "processed"
  def status_to_string(@status_failed), do: "failed"
  def status_to_string(@status_failed_with_error), do: "failed_with_error"

  def status(:pending), do: @status_pending
  def status(:processed), do: @status_processed
  def status(:failed), do: @status_failed
  def status(:failed_with_error), do: @status_failed_with_error

  def response_length, do: @response_length

  @primary_key :_id
  schema :jobs do
    field(:_id)
    field(:hash, presence: true)
    field(:eta, presence: true)
    field(:status, presence: true, inclusion: [@status_pending, @status_processed, @status_failed])
    field(:status_code, presence: true, inclusion: [200, 202, 404, 422])
    field(:response)

    timestamps()
  end

  @doc """
  Checks the validity of the response depending on its size.
  """
  @spec valid_response?(binary() | map()) :: boolean()
  def valid_response?(response) when is_binary(response) do
    byte_size(response) <= @response_length
  end

  def valid_response?(response) when is_map(response) do
    byte_size(Jason.encode!(response)) <= @response_length
  end
end
