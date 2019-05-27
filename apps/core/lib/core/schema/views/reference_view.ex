defmodule Core.ReferenceView do
  @moduledoc false

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.DateView
  alias Core.Diagnosis
  alias Core.EffectiveAt
  alias Core.Evidence
  alias Core.Executor
  alias Core.Identifier
  alias Core.Observations.Component
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value
  alias Core.Observations.Values.Quantity
  alias Core.Observations.Values.Ratio
  alias Core.Observations.Values.SampledData
  alias Core.Patients.Immunizations.Explanation
  alias Core.Patients.Immunizations.Reaction
  alias Core.Patients.Immunizations.VaccinationProtocol
  alias Core.Patients.RiskAssessments.ExtendedReference
  alias Core.Patients.RiskAssessments.Prediction
  alias Core.Patients.RiskAssessments.Probability
  alias Core.Patients.RiskAssessments.Reason
  alias Core.Patients.RiskAssessments.When
  alias Core.Period
  alias Core.Range
  alias Core.Reference
  alias Core.ServiceRequests.Occurrence
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
      target_diseases: render(vaccination_protocol.target_diseases)
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

  def render(%Coding{} = coding) do
    Map.take(coding, ~w(
      system
      code
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

  def render(%Explanation{} = explanation) do
    explanation
    |> Map.from_struct()
    |> Enum.filter(fn {_, v} -> !is_nil(v) end)
    |> Enum.into(%{}, fn {k, v} -> {k, render(v)} end)
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

  def render(%Executor{reference: value}) when not is_nil(value) do
    %{"reference" => render(value)}
  end

  def render(%Executor{text: value}) do
    %{"text" => value}
  end

  def render(%SampledData{} = value) do
    Map.take(value, ~w(
      origin
      period
      factor
      lower_limit
      upper_limit
      dimensions
      data
    )a)
  end

  def render(%Range{} = value) do
    %{low: render(value.low), high: render(value.high)}
  end

  def render(%Ratio{} = value) do
    %{
      numerator: render(value.numerator),
      denominator: render(value.denominator)
    }
  end

  def render(nil), do: nil

  def render(references) when is_list(references) do
    Enum.map(references, &render/1)
  end

  def render(value), do: value

  def render_date_period(%Period{} = period) do
    %{
      start: DateView.render_date(period.start),
      end: DateView.render_date(period.end)
    }
  end

  def render_value(%EffectiveAt{effective_date_time: value}) when not is_nil(value) do
    %{effective_date_time: DateView.render_datetime(value)}
  end

  def render_value(%Value{} = value) do
    value
    |> Map.from_struct()
    |> Enum.filter(fn {_, v} -> !is_nil(v) end)
    |> Enum.into(%{}, fn {k, v} -> {k, render(v)} end)
  end

  def render_value(nil), do: %{}

  def render_source(%{} = source) do
    source
    |> Map.from_struct()
    |> Enum.filter(fn {_, v} -> !is_nil(v) end)
    |> Enum.into(%{}, fn {k, v} -> {k, render(v)} end)
  end

  def render_source(nil), do: %{}

  def render_occurrence(%Occurrence{date_time: value}) when not is_nil(value) do
    %{occurrence_date_time: DateView.render_datetime(value)}
  end

  def render_occurrence(%Occurrence{period: value}) do
    %{occurrence_period: render(value)}
  end

  def render_occurrence(nil), do: %{}

  def render_effective_at(%EffectiveAt{effective_period: value}) when not is_nil(value) do
    %{effective_period: render(value)}
  end

  def render_effective_at(%EffectiveAt{effective_date_time: value}) do
    %{effective_date_time: DateView.render_datetime(value)}
  end

  def render_effective_at(nil), do: %{}

  def render_reason(%Reason{reason_codes: value}) when not is_nil(value) do
    %{reason_codes: render(value)}
  end

  def render_reason(%Reason{reason_references: value}) do
    %{reason_references: render(value)}
  end

  def render_reason(nil), do: %{}

  def render_probability(%Probability{probability_decimal: value}) when not is_nil(value) do
    %{probability_decimal: value}
  end

  def render_probability(%Probability{probability_range: value}) do
    %{probability_range: Map.take(value, ~w(low high)a)}
  end

  def render_probability(_), do: %{}

  def render_when(%When{when_period: value}) when not is_nil(value) do
    %{when_period: render(value)}
  end

  def render_when(%When{when_range: value}) do
    %{when_range: Map.take(value, ~w(low high)a)}
  end

  def render_when(_), do: %{}

  def remove_display_values(map) do
    map = Map.drop(map, [:display_value])

    map
    |> Map.keys()
    |> Enum.reduce(map, fn key, map ->
      value =
        map
        |> Map.get(key)
        |> process_value()

      Map.put(map, key, value)
    end)
  end

  defp process_value(value) when is_list(value), do: Enum.map(value, &process_value/1)
  defp process_value(value) when is_map(value), do: remove_display_values(value)
  defp process_value(value), do: value
end
