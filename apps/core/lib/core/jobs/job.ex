defmodule Core.Job do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @response_length 10_000

  @status_pending 0
  @status_processed 1
  @status_failed 2
  @status_failed_with_error 3

  def collection, do: "jobs"

  def status_to_string(@status_pending), do: "pending"
  def status_to_string(@status_processed), do: "processed"
  def status_to_string(@status_failed), do: "failed"
  def status_to_string(@status_failed_with_error), do: "failed_with_error"

  def status(:pending), do: @status_pending
  def status(:processed), do: @status_processed
  def status(:failed), do: @status_failed
  def status(:failed_with_error), do: @status_failed_with_error

  def response_length, do: @response_length

  @fields_required ~w(_id hash eta status status_code inserted_at updated_at)a
  @fields_optional ~w(response)a

  @primary_key {:_id, :binary_id, autogenerate: false}
  schema "jobs" do
    field(:hash, :string)
    field(:eta, :utc_datetime)
    field(:status, :string)
    field(:status_code, :integer)
    field(:response)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(%__MODULE__{} = job, params) do
    job
    |> cast(params, @fields_required ++ @fields_optional)
    |> validate_required(@fields_required)
    |> validate_inclusion(:status, [@status_pending, @status_processed, @status_failed])
    |> validate_inclusion(:status_code, [200, 202, 404, 422])
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
