defmodule Core.ReferenceView do
  @moduledoc false

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.DatePeriod
  alias Core.DateView
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
  alias Core.Patients.RiskAssessments.ExtendedReference
  alias Core.Patients.RiskAssessments.Prediction
  alias Core.Patients.RiskAssessments.Probability
  alias Core.Patients.RiskAssessments.Reason
  alias Core.Patients.RiskAssessments.When
  alias Core.Period
  alias Core.Reference
  alias Core.ServiceRequests.Occurrence
  alias Core.Source
  alias Core.Stage
  alias Core.StatusHistory
  alias Core.UUIDView

  def render(%Reference{} = reference) do
    %{
      identifier: render(reference.identifier),
      display_value: reference.display_value
    }
  end

  def render(%ExtendedReference{} = extended_reference) do
    %{
      references: Enum.map(extended_reference.references, &render/1),
      text: extended_reference.text
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

  def render(%Prediction{} = prediction) do
    prediction
    |> Map.take(~w(relative_risk rationale)a)
    |> Map.merge(%{
      outcome: render(prediction.outcome),
      qualitative_risk: render(prediction.qualitative_risk)
    })
    |> Map.merge(render_probability(prediction.probability))
    |> Map.merge(render_when(prediction.when))
  end

  def render(%Period{} = period) do
    %{
      start: DateView.render_datetime(period.start),
      end: DateView.render_datetime(period.end)
    }
  end

  def render(%DatePeriod{} = period) do
    %{
      start: DateView.render_date(period.start),
      end: DateView.render_date(period.end)
    }
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
      detail: render(reaction.detail)
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

  def render(%StatusHistory{} = status_history) do
    status_history
    |> Map.take(~w(status inserted_at)a)
    |> Map.merge(%{status_reason: render(status_history.status_reason)})
  end

  def render(nil), do: nil

  def render(references) when is_list(references) do
    Enum.map(references, &render/1)
  end

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
      dimensions
      data
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

  def render_occurrence(%Occurrence{type: "date_time", value: value}) do
    %{"occurrence_date_time" => DateView.render_datetime(value)}
  end

  def render_occurrence(%Occurrence{type: "period", value: value}) do
    %{"occurrence_period" => render(value)}
  end

  def render_effective_at(%EffectiveAt{type: "effective_date_time", value: value}) do
    %{effective_date_time: DateView.render_datetime(value)}
  end

  def render_effective_at(%EffectiveAt{type: "effective_period", value: value}) do
    %{effective_period: render(value)}
  end

  def render_reason(%Reason{type: "reason_codes", value: value}) do
    %{reason_codes: render(value)}
  end

  def render_reason(%Reason{type: "reason_references", value: value}) do
    %{reason_references: render(value)}
  end

  def render_probability(%Probability{type: "probability_decimal", value: value}) do
    %{probability_decimal: value}
  end

  def render_probability(%Probability{type: "probability_range", value: value}) do
    %{probability_range: Map.take(value, ~w(low high)a)}
  end

  def render_probability(_), do: %{}

  def render_when(%When{type: "when_period", value: value}) do
    %{when_period: render(value)}
  end

  def render_when(%When{type: "when_range", value: value}) do
    %{when_range: Map.take(value, ~w(low high)a)}
  end

  def render_when(_), do: %{}
end
