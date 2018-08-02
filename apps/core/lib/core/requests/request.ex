defmodule Core.Request do
  @moduledoc false

  use Core.Schema

  @status_processing "processing"
  @status_completed "completed"
  @status_failed "failed"

  def status(:processing), do: @status_processing
  def status(:completed), do: @status_completed
  def status(:failed), do: @status_failed

  @primary_key :_id
  schema :requests do
    field(:_id)
    field(:status, presence: true)
    field(:response)
  end
end
