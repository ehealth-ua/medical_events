defmodule Api.Web.ObservationController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Observation
  alias Core.Observations
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: observations} = paging} <- Observations.list(params) do
      render(conn, "index.json", observations: observations, paging: paging)
    end
  end

  def show(conn, %{"patient_id" => patient_id, "id" => observation_id}) do
    with {:ok, %Observation{} = observation} <- Observations.get_by_id(patient_id, observation_id) do
      render(conn, "show.json", observation: observation)
    end
  end
end
