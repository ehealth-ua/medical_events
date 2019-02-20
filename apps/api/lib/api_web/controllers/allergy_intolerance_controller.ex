defmodule Api.Web.AllergyIntoleranceController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Patients.AllergyIntolerances
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: allergy_intolerances} = paging} <- AllergyIntolerances.list(params) do
      render(conn, "index.json", allergy_intolerances: allergy_intolerances, paging: paging)
    end
  end

  def show(conn, %{"patient_id_hash" => patient_id_hash, "id" => allergy_intolerance_id}) do
    with {:ok, allergy_intolerance} <- AllergyIntolerances.get_by_id(patient_id_hash, allergy_intolerance_id) do
      render(conn, "show.json", allergy_intolerance: allergy_intolerance)
    end
  end

  def show_by_episode(conn, params) do
    %{"patient_id_hash" => patient_id_hash, "id" => allergy_intolerance_id, "episode_id" => episode_id} = params

    with {:ok, allergy_intolerance} <-
           AllergyIntolerances.get_by_id_episode_id(patient_id_hash, allergy_intolerance_id, episode_id) do
      render(conn, "show.json", allergy_intolerance: allergy_intolerance)
    end
  end
end
