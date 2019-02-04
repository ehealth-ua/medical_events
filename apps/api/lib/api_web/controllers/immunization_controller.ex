defmodule Api.Web.ImmunizationController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Patients.Immunizations
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: immunizations} = paging} <- Immunizations.list(params) do
      render(conn, "index.json", immunizations: immunizations, paging: paging)
    end
  end

  def show(conn, %{"patient_id_hash" => patient_id_hash, "id" => immunization_id}) do
    with {:ok, immunization} <- Immunizations.get_by_id(patient_id_hash, immunization_id) do
      render(conn, "show.json", immunization: immunization)
    end
  end
end
