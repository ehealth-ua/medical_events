defmodule Api.Web.ReferenceView do
  @moduledoc false

  alias Core.CodeableConcept
  alias Core.Coding
  alias Core.Evidence
  alias Core.Identifier
  alias Core.Observations.Component
  alias Core.Observations.EffectiveAt
  alias Core.Observations.ReferenceRange
  alias Core.Observations.Value
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
      value: identifier.value
    }
  end

  def render(%ReferenceRange{} = reference_range) do
    fields = ~w(
      low
      high
      age
      text
    )a

    reference_range
    |> Map.take(fields)
    |> Map.put(:type, render(reference_range.type))
    |> Map.put(:applies_to, render(reference_range.type))
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

  def render(%Period{} = period) do
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

  def render(%Stage{} = stage) do
    %{
      summary: render(stage.summary)
    }
  end

  def render(nil), do: nil

  def render(references) when is_list(references) do
    Enum.map(references, &render/1)
  end

  def render_value(%Value{type: "codeable_concept", value: value}) do
    %{"value_codeable_concept" => render(value)}
  end

  def render_value(%Value{type: "quantity", value: value}) do
    fields = ~w(
      value
      comparator
      unit
      system
      code
    )a

    %{"value_quantity" => Map.take(value, fields)}
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

    %{"value_sampled_data" => Map.take(value, fields)}
  end

  def render_value(%Value{type: "range", value: value}) do
    %{"value_range" => Map.take(value, ~w(low high)a)}
  end

  def render_value(%Value{type: "ratio", value: value}) do
    %{"value_ratio" => Map.take(value, ~w(numerator denominator)a)}
  end

  def render_value(%Value{type: "period", value: value}) do
    %{"value_period" => render(value)}
  end

  def render_value(%Value{type: type, value: value}) do
    %{("value_" <> type) => value}
  end

  def render_source(%Source{type: type, value: value}) do
    %{type => render(value)}
  end

  def render_effective_at(%EffectiveAt{type: "effective_date_time", value: value}) do
    %{"effective_date_time" => value}
  end

  def render_effective_at(%EffectiveAt{type: "effective_period", value: value}) do
    %{"effective_period" => render(value)}
  end
end
