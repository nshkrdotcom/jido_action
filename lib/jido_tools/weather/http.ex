defmodule Jido.Tools.Weather.HTTP do
  @moduledoc false

  alias Jido.Action.Error

  @geojson_headers %{
    "User-Agent" => "jido_action/1.0 (weather tool)",
    "Accept" => "application/geo+json"
  }

  @json_headers %{
    "User-Agent" => "jido_action/1.0 (weather tool)",
    "Accept" => "application/json"
  }

  @spec geojson_headers() :: map()
  def geojson_headers, do: @geojson_headers

  @spec json_headers() :: map()
  def json_headers, do: @json_headers

  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def get(url, opts \\ []) when is_binary(url) and is_list(opts) do
    headers = Keyword.get(opts, :headers, @geojson_headers)
    params = Keyword.get(opts, :params)
    error_prefix = Keyword.get(opts, :error_prefix, "HTTP error")

    req_options =
      [method: :get, url: url, headers: headers]
      |> maybe_put_params(params)

    try do
      {:ok, Req.request!(req_options)}
    rescue
      e ->
        {:error,
         Error.execution_error("#{error_prefix}: #{Exception.message(e)}", %{
           url: url,
           params: params,
           headers: headers,
           exception: e
         })}
    end
  end

  @spec status_error(String.t(), integer(), any()) :: {:error, Exception.t()}
  def status_error(prefix, status, body) when is_binary(prefix) and is_integer(status) do
    {:error,
     Error.execution_error("#{prefix} (#{status}): #{inspect(body)}", %{
       status: status,
       body: body
     })}
  end

  defp maybe_put_params(opts, nil), do: opts
  defp maybe_put_params(opts, params), do: Keyword.put(opts, :params, params)
end
