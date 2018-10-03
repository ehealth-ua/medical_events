defmodule Api.Web.Plugs.PatientIdHasher do
  @moduledoc """
  Hashes patient._id and all patient_id references in params
  """

  alias Core.Patients
  alias Plug.Conn

  def init(opts), do: opts

  def call(%Conn{params: params} = conn, _opts) do
    patient_id = Map.get(params, "patient_id")

    case patient_id do
      nil -> conn
      _ -> %{conn | params: Map.put(params, "patient_id_hash", Patients.get_pk_hash(patient_id))}
    end
  end
end
