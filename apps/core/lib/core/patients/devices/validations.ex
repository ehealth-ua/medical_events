defmodule Core.Patients.Devices.Validations do
  @moduledoc false

  import Core.Schema, only: [add_validations: 3]

  alias Core.Device
  alias Core.Period
  alias Core.Reference
  alias Core.Source

  def validate_asserted_date(%Device{} = device) do
    now = DateTime.utc_now()
    max_days_passed = Confex.fetch_env!(:core, :encounter_package)[:device_max_days_passed]

    add_validations(device, :asserted_date,
      datetime: [less_than_or_equal_to: now, message: "Asserted date must be in past"],
      max_days_passed: [max_days_passed: max_days_passed]
    )
  end

  def validate_context(%Device{context: context} = device, encounter_id) do
    identifier =
      add_validations(context.identifier, :value,
        value: [equals: encounter_id, message: "Submitted context is not allowed for the device"]
      )

    %{device | context: %{context | identifier: identifier}}
  end

  def validate_source(%Device{source: %Source{type: "asserter"}} = device, client_id) do
    device =
      add_validations(
        device,
        :source,
        source: [primary_source: device.primary_source, primary_required: "asserter"]
      )

    source = device.source
    source = %{source | value: validate_asserter(source.value, client_id)}
    %{device | source: source}
  end

  def validate_source(%Device{} = device, _) do
    add_validations(device, :source, source: [primary_source: device.primary_source])
  end

  def validate_asserter(%Reference{} = asserter, client_id) do
    identifier =
      add_validations(
        asserter.identifier,
        :value,
        employee: [
          type: "DOCTOR",
          status: "APPROVED",
          legal_entity_id: client_id,
          messages: [
            type: "Employee is not an active doctor",
            status: "Employee is not an active doctor",
            legal_entity_id: "Employee #{asserter.identifier.value} doesn't belong to your legal entity"
          ]
        ]
      )

    %{asserter | identifier: identifier}
  end

  def validate_usage_period(%Device{usage_period: %Period{} = usage_period} = device) do
    now = DateTime.utc_now()

    usage_period =
      add_validations(
        usage_period,
        :start,
        datetime: [less_than_or_equal_to: now, message: "Start date must be in past"]
      )

    usage_period =
      if usage_period.end do
        add_validations(
          usage_period,
          :end,
          datetime: [less_than_or_equal_to: now, message: "End date must be in past"],
          datetime: [greater_than: usage_period.start, message: "End date must be greater than the start date"]
        )
      else
        usage_period
      end

    %{device | usage_period: usage_period}
  end
end
