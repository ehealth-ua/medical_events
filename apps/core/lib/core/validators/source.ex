defmodule Core.Validators.Source do
  @moduledoc false

  use Vex.Validator
  alias Core.Source, as: SourceSchema

  def validate(%SourceSchema{} = source, options) do
    primary_source = Keyword.get(options, :primary_source)
    primary_required = Keyword.get(options, :primary_required)

    if primary_source do
      expect_primary_required(source, primary_required, options)
    else
      expect_report_origin(source, options)
    end
  end

  def validate(_, _), do: :ok

  def error(options, error_message) do
    {:error, message(options, error_message)}
  end

  defp expect_primary_required(%SourceSchema{type: primary_required}, primary_required, _), do: :ok

  defp expect_primary_required(_, primary_required, options) do
    error(options, "#{primary_required} must be present if primary_source is true")
  end

  defp expect_report_origin(%SourceSchema{type: "report_origin"}, _), do: :ok

  defp expect_report_origin(_, options) do
    error(options, "report_origin must be present if primary_source is false")
  end
end
