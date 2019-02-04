defmodule Api.Web.DeviceView do
  @moduledoc false

  use ApiWeb, :view

  alias Core.DateView
  alias Core.ReferenceView
  alias Core.UUIDView

  def render("index.json", %{devices: devices}) do
    render_many(devices, __MODULE__, "show.json", as: :device)
  end

  def render("show.json", %{device: device}) do
    device_fields = ~w(
      status
      primary_source
      lot_number
      manufacturer
      model
      version
      note
      inserted_at
      updated_at
    )a

    device_data = %{
      id: UUIDView.render(device.id),
      context: ReferenceView.render(device.context),
      asserted_date: DateView.render_datetime(device.asserted_date),
      usage_period: ReferenceView.render(device.usage_period),
      type: ReferenceView.render(device.type),
      manufacture_date: DateView.render_datetime(device.manufacture_date),
      expiration_date: DateView.render_datetime(device.expiration_date)
    }

    device
    |> Map.take(device_fields)
    |> Map.merge(device_data)
    |> Map.merge(ReferenceView.render_source(device.source))
  end
end
