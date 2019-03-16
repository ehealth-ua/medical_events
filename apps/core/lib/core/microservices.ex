defmodule Core.Microservices do
  @moduledoc false

  @success_codes [200, 201, 204]

  require Logger
  alias Core.Microservices.Error

  defmacro __using__(_) do
    quote do
      use Confex, otp_app: :core
      use HTTPoison.Base
      require Logger
      import Core.Microservices

      def process_url(url), do: config()[:endpoint] <> url

      def process_request_options(options), do: Keyword.merge(config()[:hackney_options], options)

      def process_request_headers(headers) do
        headers
        |> Keyword.take(~w(request_id x-consumer-metadata x-consumer-id)a)
        |> Kernel.++([{"Content-Type", "application/json"}])
      end

      def request(method, url, body \\ "", headers \\ [], options \\ []) do
        with {:ok, params} <- check_params(options) do
          query_string = if Enum.empty?(params), do: "", else: "?#{URI.encode_query(params)}"
          endpoint = config()[:endpoint]
          path = Enum.join([process_url(url), query_string])

          headers =
            Enum.reduce(process_request_headers(headers), %{}, fn {k, v}, map ->
              Map.put_new(map, k, v)
            end)

          Logger.info(
            "Microservice #{method} request to #{endpoint} on #{path} with body: #{body}, headers: #{headers}"
          )

          check_response(super(method, url, body, headers, options))
        end
      end

      defp check_params(options) do
        params = Keyword.get(options, :params, [])

        errors =
          Enum.reduce(params, [], fn
            {k, v}, errors_list when is_list(v) ->
              errors_list ++ error_description(k)

            {k, v}, errors_list ->
              try do
                to_string(v)
                errors_list
              rescue
                error ->
                  errors_list ++ error_description(k)
              end
          end)

        if length(errors) > 0, do: {:error, errors}, else: {:ok, params}
      end

      defp error_description(value_name) do
        [
          {
            %{
              description: "Request parameter #{value_name} is not valid",
              params: [],
              rule: :invalid
            },
            "$.#{value_name}"
          }
        ]
      end
    end
  end

  def check_response({:ok, %HTTPoison.Response{status_code: status_code, body: body}})
      when status_code in @success_codes do
    decode_response(body)
  end

  def check_response({:ok, %HTTPoison.Response{body: body}}) do
    case decode_response(body) do
      {:ok, body} -> {:error, body}
      error -> error
    end
  end

  def check_response({:error, %HTTPoison.Error{reason: reason}}) do
    raise Error, message: reason
  end

  # no body in response
  def decode_response(""), do: {:ok, ""}

  def decode_response(response) do
    case Jason.decode(response) do
      {:ok, body} ->
        {:ok, body}

      err ->
        Logger.error(err)
        {:error, {:response_json_decoder, response}}
    end
  end
end
