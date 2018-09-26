defmodule Core.ReferenceView do
  @moduledoc false

  alias Api.Web.UUIDView
  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.DatePeriod
  alias Core.Diagnosis
  alias Core.Evidence
  alias Core.Identifier
  alias Core.Observations.Component
  alias Core.Observations.EffectiveAt
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value
  alias Core.Observations.Values.Quantity
  alias Core.Patients.Immunizations.Explanation
  alias Core.Patients.Immunizations.Reaction
  alias Core.Patients.Immunizations.VaccinationProtocol
  alias Core.Period
  alias Core.Reference
  alias Core.Source
  alias Core.Stage

  def render(%Reference{} = reference) do
    %{
      identifier: render(reference.identifier),
      display_value: reference.display_value
    }
  end

  def render(%Identifier{} = identifier) do
    %{
      type: render(identifier.type),
      value: UUIDView.render(identifier.value)
    }
  end

  def render(%ReferenceRange{} = reference_range) do
    %{
      low: render(reference_range.low),
      high: render(reference_range.high),
      age: %{
        low: render(reference_range.age.low),
        high: render(reference_range.age.high)
      },
      type: render(reference_range.type),
      applies_to: render(reference_range.applies_to),
      text: reference_range.text
    }
  end

  def render(%CodeableConcept{} = codeable_concept) do
    %{
      coding: render(codeable_concept.coding),
      text: codeable_concept.text
    }
  end

  def render(%Component{} = component) do
    %{
      code: render(component.code),
      interpretation: render(component.interpretation),
      reference_ranges: render(component.reference_ranges)
    }
    |> Map.merge(render_value(component.value))
  end

  def render(%VaccinationProtocol{} = vaccination_protocol) do
    vaccination_protocol
    |> Map.take(~w(dose_sequence description series series_doses)a)
    |> Map.merge(%{
      authority: render(vaccination_protocol.authority),
      target_diseases: render(vaccination_protocol.target_diseases),
      dose_status: render(vaccination_protocol.dose_status),
      dose_status_reason: render(vaccination_protocol.dose_status_reason)
    })
  end

  def render(%Period{} = period) do
    Map.take(period, ~w(
      start
      end
    )a)
  end

  def render(%DatePeriod{} = period) do
    Map.take(period, ~w(
      start
      end
    )a)
  end

  def render(%Coding{} = coding) do
    Map.take(coding, ~w(
      system
      code
      display
    )a)
  end

  def render(%Evidence{} = evidence) do
    %{
      codes: render(evidence.codes),
      details: render(evidence.details)
    }
  end

  def render(%Reaction{} = reaction) do
    %{
      date: render_date(reaction.date),
      detail: render(reaction.detail),
      reported: reaction.reported
    }
  end

  def render(%Stage{} = stage) do
    %{
      summary: render(stage.summary)
    }
  end

  def render(%Diagnosis{} = diagnosis) do
    %{
      rank: diagnosis.rank,
      condition: render(diagnosis.condition),
      role: render(diagnosis.role),
      code: render(diagnosis.code)
    }
  end

  def render(%Explanation{type: type, value: value}) do
    %{type: type, value: render(value)}
  end

  def render(%Quantity{} = quantity) do
    Map.take(quantity, ~w(
      value
      comparator
      unit
      system
      code
    )a)
  end

  def render(nil), do: nil

  def render(references) when is_list(references) do
    Enum.map(references, &render/1)
  end

  def render_date(nil), do: nil
  def render_date(date) when is_binary(date), do: date
  def render_date(%Date{} = date), do: to_string(date)
  def render_date(%DateTime{} = date_time), do: date_time |> DateTime.to_date() |> to_string()

  def render_datetime(nil), do: nil
  def render_datetime(%DateTime{} = date_time), do: date_time |> to_string()
  def render_datetime(date_time) when is_binary(date_time), do: date_time

  def render_value(%Value{type: "codeable_concept", value: value}) do
    %{value_codeable_concept: render(value)}
  end

  def render_value(%Value{type: "quantity", value: value}) do
    fields = ~w(
      value
      comparator
      unit
      system
      code
    )a

    %{value_quantity: Map.take(value, fields)}
  end

  def render_value(%Value{type: "sampled_data", value: value}) do
    fields = ~w(
      origin
      period
      factor
      lower_limit
      upper_limit
      dimensions data
    )a

    %{value_sampled_data: Map.take(value, fields)}
  end

  def render_value(%Value{type: "range", value: value}) do
    %{value_range: Map.take(value, ~w(low high)a)}
  end

  def render_value(%Value{type: "ratio", value: value}) do
    %{value_ratio: Map.take(value, ~w(numerator denominator)a)}
  end

  def render_value(%Value{type: "period", value: value}) do
    %{value_period: render(value)}
  end

  def render_value(%Value{type: type, value: value}) do
    %{String.to_atom("value_" <> type) => UUIDView.render(value)}
  end

  def render_source(%Source{type: type, value: value}) do
    %{String.to_atom(type) => render(value)}
  end

  def render_effective_at(%EffectiveAt{type: "effective_date_time", value: value}) do
    %{effective_date_time: value}
  end

  def render_effective_at(%EffectiveAt{type: "effective_period", value: value}) do
    %{effective_period: render(value)}
  end
end
