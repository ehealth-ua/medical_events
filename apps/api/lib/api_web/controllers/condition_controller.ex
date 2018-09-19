defmodule Api.Web.ConditionController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Conditions
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: conditions} = paging} <- Conditions.list(params) do
      render(conn, "index.json", conditions: conditions, paging: paging)
    end
  end

  def show(conn, %{"patient_id" => patient_id, "id" => condition_id}) do
    with {:ok, condition} <- Conditions.get(patient_id, condition_id) do
      render(conn, "show.json", condition: condition)
    end
  end
end
