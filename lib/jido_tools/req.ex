defmodule Jido.Tools.ReqTool do
  @moduledoc """
  A behavior and macro for creating HTTP request tools using the Req library.

  Provides a standardized way to create actions that make HTTP requests with
  configurable URL, method, headers, and JSON parsing options.
  """

  alias Jido.Action.Config
  alias Jido.Action.Error
  alias Jido.Action.TimeoutBudget

  @req_config_schema NimbleOptions.new!(
                       url: [type: :string, required: true],
                       method: [type: {:in, [:get, :post, :put, :delete]}, required: true],
                       headers: [
                         type: {:map, :string, :string},
                         default: %{},
                         doc: "HTTP headers to include in the request"
                       ],
                       json: [
                         type: :boolean,
                         default: true,
                         doc: "Whether to parse the response as JSON"
                       ]
                     )

  @doc """
  Callback for transforming the HTTP response result.

  Takes a map with request and response data and returns a transformed result.
  """
  @callback transform_result(map()) :: {:ok, map()} | {:error, any()}

  # Make transform_result optional
  @optional_callbacks [transform_result: 1]

  @doc """
  Macro for setting up a module as a ReqTool with HTTP request capabilities.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@req_config_schema)

    quote location: :keep do
      req_keys = [:url, :method, :headers, :json]
      req_opts = Keyword.take(unquote(opts), req_keys)
      action_opts = Keyword.drop(unquote(opts), req_keys)

      case NimbleOptions.validate(req_opts, unquote(escaped_schema)) do
        {:ok, validated_req_opts} ->
          @behaviour Jido.Tools.ReqTool

          use Jido.Action, action_opts
          alias Jido.Tools.ReqTool
          @req_opts validated_req_opts

          @impl Jido.Action
          def run(params, context) do
            case ReqTool.make_request(@req_opts, params, context) do
              {:ok, response} ->
                result = %{
                  request: %{
                    url: @req_opts[:url],
                    method: @req_opts[:method],
                    params: params
                  },
                  response: %{
                    status: response.status,
                    body: response.body,
                    headers: response.headers
                  }
                }

                transform_result(result)

              {:error, reason} ->
                {:error, reason}
            end
          end

          @impl Jido.Tools.ReqTool
          def transform_result(result) do
            {:ok, result}
          end

          defoverridable transform_result: 1

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "ReqTool", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end

  @doc false
  def make_request(req_opts, params, context) do
    method = req_opts[:method]
    url = req_opts[:url]
    headers = req_opts[:headers]
    json = req_opts[:json]
    timeout_ms = resolve_request_timeout_ms(context)

    if Code.ensure_loaded?(Req) do
      dispatch_request(method, url, headers, json, timeout_ms, params)
    else
      {:error,
       Error.config_error(
         "Req library is required for ReqTool. Add {:req, \"~> 0.5\"} to your deps.",
         %{dependency: :req}
       )}
    end
  end

  defp dispatch_request(_method, url, _headers, _json, 0 = timeout_ms, _params) do
    {:error,
     Error.timeout_error("HTTP request deadline exceeded before dispatch", %{
       timeout: timeout_ms,
       url: url
     })}
  end

  defp dispatch_request(method, url, headers, json, timeout_ms, params) do
    req_options =
      [method: method, url: url, headers: headers]
      |> Keyword.put(:connect_options, timeout: timeout_ms)
      |> Keyword.put(:receive_timeout, timeout_ms)
      |> Keyword.put(:pool_timeout, timeout_ms)

    req_options =
      if json, do: Keyword.put(req_options, :decode_json, json), else: req_options

    req_options =
      case method do
        m when m in [:post, :put] ->
          Keyword.put(req_options, :json, params)

        _ ->
          Keyword.put(req_options, :params, params)
      end

    response = Req.request!(req_options)
    {:ok, response}
  rescue
    e ->
      {:error,
       Error.execution_error("HTTP request failed", %{
         exception: e,
         timeout: timeout_ms,
         url: url
       })}
  end

  defp resolve_request_timeout_ms(context) do
    case TimeoutBudget.timeout_ms_from_context(context) do
      value when is_integer(value) and value >= 0 -> value
      _ -> Config.exec_timeout()
    end
  end
end
