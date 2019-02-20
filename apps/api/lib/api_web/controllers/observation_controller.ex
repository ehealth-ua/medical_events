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

  def show(conn, %{"patient_id_hash" => patient_id_hash, "id" => observation_id}) do
    with {:ok, %Observation{} = observation} <- Observations.get_by_id(patient_id_hash, observation_id) do
      render(conn, "show.json", observation: observation)
    end
  end

  def show_by_episode(conn, params) do
    %{"patient_id_hash" => patient_id_hash, "id" => observation_id, "episode_id" => episode_id} = params

    with {:ok, observation} <- Observations.get_by_id_episode_id(patient_id_hash, observation_id, episode_id) do
      render(conn, "show.json", observation: observation)
    end
  end
end
