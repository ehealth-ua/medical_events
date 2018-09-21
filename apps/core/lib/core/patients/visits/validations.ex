defmodule Core.Patients.Visits.Validations do
  @moduledoc false

  alias Core.Visit
  import Core.Schema, only: [add_validations: 3]

  def validate_period(%Visit{} = visit) do
    now = DateTime.utc_now()

    period =
      visit.period
      |> add_validations(
        :start,
        datetime: [less_than_or_equal_to: now, message: "Start date must be in past"]
      )
      |> add_validations(
        :end,
        presence: true,
        datetime: [less_than_or_equal_to: now, message: "End date must be in past"],
        datetime: [greater_than: visit.period.start, message: "End date must be greater than the start date"]
      )

    %{visit | period: period}
  end
end
