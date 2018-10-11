defmodule Core.Validators.Signature do
  @moduledoc false

  def validate(%{"content" => content, "signatures" => signatures}, required_signatures \\ 1)
      when is_list(signatures) do
    if Enum.count(signatures) == required_signatures do
      # return the last signature (they are in reverse order)
      get_last_signer(content, List.first(signatures))
    else
      signer_message = if required_signatures == 1, do: "signer", else: "signers"

      {:error,
       {:bad_request,
        "document must be signed by #{required_signatures} #{signer_message} but contains #{Enum.count(signatures)} signatures"}}
    end
  end

  def validate_drfo(drfo, tax_id) do
    drfo = String.replace(drfo, " ", "")

    if tax_id == drfo || translit(tax_id) == translit(drfo) do
      :ok
    else
      {:error, "Does not match the signer drfo"}
    end
  end

  defp translit(string) do
    string
    |> Translit.translit()
    |> String.upcase()
  end

  defp get_last_signer(content, %{"is_valid" => true, "signer" => signer}) do
    {:ok, %{"content" => content, "signer" => signer}}
  end

  defp get_last_signer(_, %{"is_valid" => false, "validation_error_message" => error}),
    do: {:error, {:bad_request, error}}
end
