defmodule Jido.Tools.Weather.HTTP do
  @moduledoc false

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Action.TimeoutBudget

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
    timeout_ms = resolve_timeout_ms(Keyword.get(opts, :timeout_ms), Keyword.get(opts, :context))

    if timeout_ms == 0 do
      {:error,
       Error.timeout_error("#{error_prefix}: request deadline exceeded before dispatch", %{
         url: url,
         timeout: timeout_ms
       })}
    else
      req_options =
        [method: :get, url: url, headers: headers]
        |> maybe_put_params(params)
        |> Keyword.put(:connect_options, timeout: timeout_ms)
        |> Keyword.put(:receive_timeout, timeout_ms)
        |> Keyword.put(:pool_timeout, timeout_ms)

      try do
        {:ok, Req.request!(req_options)}
      rescue
        e ->
          {:error,
           Error.execution_error("#{error_prefix}: #{Exception.message(e)}", %{
             url: url,
             params: params,
             headers: headers,
             timeout: timeout_ms,
             exception: e
           })}
      end
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

  defp resolve_timeout_ms(timeout_ms, context) do
    context_timeout =
      if is_map(context) do
        TimeoutBudget.timeout_ms_from_context(context)
      else
        nil
      end

    first_positive_or_zero([timeout_ms, context_timeout, Config.exec_timeout()]) ||
      Config.exec_timeout()
  end

  defp first_positive_or_zero(values) when is_list(values) do
    Enum.find(values, fn
      value when is_integer(value) and value >= 0 -> true
      _ -> false
    end)
  end
end
