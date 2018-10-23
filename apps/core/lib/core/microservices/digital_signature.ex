defmodule Core.Microservices.DigitalSignature do
  @moduledoc false

  use Core.Microservices
  import Core.Headers

  @behaviour Core.Behaviours.DigitalSignatureBehaviour

  def decode(signed_content, headers) do
    if config()[:enabled] do
      params = %{
        "signed_content" => signed_content,
        "signed_content_encoding" => "base64"
      }

      headers = Keyword.merge(headers, "Content-Type": "application/json")

      post("/digital_signatures", Jason.encode!(params), headers)
    else
      with {:ok, binary} <- Base.decode64(signed_content),
           {:ok, data} <- Jason.decode(binary) do
        data_is_valid_resp(data, headers)
      else
        _ ->
          data_is_invalid_resp()
      end
    end
  end

  defp data_is_valid_resp(data, headers) do
    signatures = [
      %{
        "is_valid" => true,
        "signer" => %{
          "drfo" => get_header(headers, "drfo"),
          "edrpou" => get_header(headers, "edrpou")
        },
        "validation_error_message" => ""
      }
    ]

    data =
      %{
        "content" => data,
        "signatures" => signatures
      }
      |> wrap_response(200)
      |> Jason.encode!()

    check_response({:ok, %HTTPoison.Response{body: data, status_code: 200}})
  end

  defp data_is_invalid_resp(path \\ "$.signed_content") do
    data =
      %{
        "error" => %{
          "invalid" => [
            %{
              "entry" => path,
              "entry_type" => "json_data_property",
              "rules" => [
                %{
                  "description" => "Not a base64 string",
                  "params" => [],
                  "rule" => "invalid"
                }
              ]
            }
          ],
          "message" =>
            "Validation failed. You can find validators description at our API Manifest:" <>
              " http://docs.apimanifest.apiary.io/#introduction/interacting-with-api/errors.",
          "type" => "validation_failed"
        },
        "meta" => %{
          "code" => 422,
          "request_id" => "2kmaguf9ec791885t40008s2",
          "type" => "object",
          "url" => "http://www.example.com/digital_signatures"
        }
      }
      |> Jason.encode!()

    check_response({:ok, %HTTPoison.Response{body: data, status_code: 422}})
  end

  defp wrap_response(data, code) do
    %{
      "meta" => %{
        "code" => code,
        "type" => "list"
      },
      "data" => data
    }
  end
end
