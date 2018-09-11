defmodule Core.Observations.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]
  alias Core.Observation
  alias Core.Observations.Value
  alias Core.Period

  def validate_issued(%Observation{} = observation) do
    now = DateTime.utc_now()

    add_validations(
      observation,
      :issued,
      datetime: [less_than_or_equal_to: now, message: "Issued datetime must be in past"]
    )
  end

  def validate_context(%Observation{context: context} = observation, encounter_id) do
    identifier =
      add_validations(
        context.identifier,
        :value,
        value: [equals: encounter_id, message: "Submitted context is not allowed for the observation"]
      )

    %{observation | context: %{context | identifier: identifier}}
  end

  def validate_performer(%Observation{performer: nil} = observation), do: observation

  def validate_performer(%Observation{_id: id, performer: performer} = observation) do
    identifier =
      add_validations(performer.identifier, :value, employee: [ets_key: "observation_#{id}_performer_employee"])

    %{observation | performer: %{performer | identifier: identifier}}
  end

  def validate_value(%Observation{value: %Value{type: type, value: %Period{}} = value} = observation) do
    add_validations(
      %{observation | value: %{value | value: validate_period(value.value)}},
      :value,
      reference: [path: type]
    )
  end

  def validate_value(%Observation{value: %Value{type: type}} = observation) do
    add_validations(observation, :value, reference: [path: type])
  end

  def validate_value(%Observation{} = observation), do: observation

  def validate_effective_period(%Observation{effective_period: nil} = observation), do: observation

  def validate_effective_period(%Observation{effective_period: period} = observation) do
    %{observation | effective_period: validate_period(period)}
  end

  defp validate_period(%Period{} = period) do
    now = DateTime.utc_now()

    period =
      add_validations(
        period,
        :start,
        datetime: [less_than_or_equal_to: now, message: "Start date must be in past"]
      )

    if period.end do
      add_validations(
        period,
        :end,
        datetime: [less_than_or_equal_to: now, message: "End date must be in past"],
        datetime: [greater_than: period.start, message: "End date must be greater than the start date"]
      )
    else
      period
    end
  end
end
