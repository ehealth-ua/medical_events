defmodule Api.Web.Plugs.PatientExists do
  @moduledoc """
  Hashes patient._id and all patient_id references in params
  """

  import Plug.Conn
  alias Api.Web.FallbackController
  alias Core.Patients
  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{params: params} = conn, _opts) do
    case Patients.get_by_id(Map.get(params, "patient_id_hash"), projection: [_id: true]) do
      nil ->
        conn
        |> FallbackController.call(nil)
        |> halt()

      _ ->
        conn
    end
  end
end
