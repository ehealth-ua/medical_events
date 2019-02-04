defmodule Api.Web.DeviceController do
  @moduledoc false

  use ApiWeb, :controller

  alias Core.Patients.Devices
  alias Scrivener.Page

  action_fallback(Api.Web.FallbackController)

  def index(conn, params) do
    with {:ok, %Page{entries: devices} = paging} <- Devices.list(params) do
      render(conn, "index.json", devices: devices, paging: paging)
    end
  end

  def show(conn, %{"patient_id_hash" => patient_id_hash, "id" => device_id}) do
    with {:ok, device} <- Devices.get_by_id(patient_id_hash, device_id) do
      render(conn, "show.json", device: device)
    end
  end
end
