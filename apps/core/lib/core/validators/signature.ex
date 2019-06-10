defmodule Core.Validators.Signature do
  @moduledoc false

  alias Core.ValidationError
  alias Core.Validators.Error

  def validate(%{content: content, signatures: signatures}, required_signatures \\ 1)
      when is_list(signatures) do
    if Enum.count(signatures) == required_signatures do
      # return the last signature (they are in reverse order)
      get_last_signer(content, List.first(signatures))
    else
      signer_message = if required_signatures == 1, do: "signer", else: "signers"

      Error.dump(%ValidationError{
        description:
          "document must be signed by #{required_signatures} #{signer_message} but contains #{Enum.count(signatures)} signatures",
        path: "$.signed_data"
      })
    end
  end

  def validate_drfo(drfo, tax_id) when is_binary(drfo) and is_binary(tax_id) do
    drfo = String.replace(drfo, " ", "")

    if tax_id == drfo || translit(tax_id) == translit(drfo) do
      :ok
    else
      {:error, "Does not match the signer drfo", 409}
    end
  end

  def validate_drfo(_, _), do: {:error, "Does not match the signer drfo", 409}

  defp translit(string) do
    string
    |> Translit.translit()
    |> String.upcase()
  end

  defp get_last_signer(content, %{is_valid: true, signer: signer}) do
    {:ok, %{content: content, signer: signer}}
  end

  defp get_last_signer(_, %{is_valid: false, validation_error_message: error}) do
    Error.dump(%ValidationError{
      description: error,
      path: "$.signed_data"
    })
  end
end
