defmodule Api.Web.SummaryController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.AllergyIntoleranceView
  alias Api.Web.ConditionView
  alias Api.Web.ImmunizationView
  alias Core.Conditions
  alias Core.Patients.AllergyIntolerances
  alias Core.Patients.Immunizations
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def list_immunizations(conn, params) do
    with {:ok, %Page{entries: immunizations} = paging} <- Immunizations.list(params, :immunization_summary) do
      render(conn, ImmunizationView, "index.json", immunizations: immunizations, paging: paging)
    end
  end

  def list_allergy_intolerances(conn, params) do
    with {:ok, %Page{entries: allergy_intolerances} = paging} <-
           AllergyIntolerances.list(params, :allergy_intolerance_summary) do
      render(conn, AllergyIntoleranceView, "index.json", allergy_intolerances: allergy_intolerances, paging: paging)
    end
  end

  def list_conditions(conn, params) do
    with {:ok, %Page{entries: conditions} = paging} <- Conditions.summary(params) do
      render(conn, ConditionView, "index.json", conditions: conditions, paging: paging)
    end
  end

  def show_condition(conn, %{"patient_id_hash" => patient_id_hash, "id" => condition_id}) do
    with {:ok, condition} <- Conditions.get_summary(patient_id_hash, condition_id) do
      render(conn, ConditionView, "show.json", condition: condition)
    end
  end
end
