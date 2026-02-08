defmodule Jido.Tools.ReqTool do
  @moduledoc """
  A behavior and macro for creating HTTP request tools using the Req library.

  Provides a standardized way to create actions that make HTTP requests with
  configurable URL, method, headers, and JSON parsing options.
  """

  alias Jido.Action.Error

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
      # Separate ReqTool-specific options from base Action options
      req_keys = [:url, :method, :headers, :json]
      req_opts = Keyword.take(unquote(opts), req_keys)
      action_opts = Keyword.drop(unquote(opts), req_keys)

      # Validate ReqTool-specific options
      case NimbleOptions.validate(req_opts, unquote(escaped_schema)) do
        {:ok, validated_req_opts} ->
          @behaviour Jido.Tools.ReqTool

          use Jido.Action, action_opts
          # Store validated req opts for later use
          @req_opts validated_req_opts

          # Pass the remaining options to the base Action

          # Implement the behavior

          # Implement the run function that uses req options
          @impl Jido.Action
          def run(params, context) do
            # Make the actual HTTP request using Req
            req_result = make_request(params, context)

            case req_result do
              {:ok, response} ->
                # Create a standardized result structure
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

                # Call transform_result, which will either use our default implementation
                # or the user's custom implementation
                transform_result(result)

              {:error, reason} ->
                {:error, reason}
            end
          end

          # Helper function to make the actual HTTP request
          defp make_request(params, context) do
            # Build the request based on the method
            method = @req_opts[:method]
            url = @req_opts[:url]
            headers = @req_opts[:headers]
            json = @req_opts[:json]
            timeout_ms = resolve_request_timeout_ms(context)

            # Ensure Req is available
            if Code.ensure_loaded?(Req) do
              if timeout_ms == 0 do
                {:error,
                 Error.timeout_error("HTTP request deadline exceeded before dispatch", %{
                   timeout: timeout_ms,
                   url: url
                 })}
              else
                try do
                  # Build options for Req
                  req_options = [
                    method: method,
                    url: url,
                    headers: headers
                  ]

                  req_options =
                    req_options
                    |> Keyword.put(:connect_options, timeout: timeout_ms)
                    |> Keyword.put(:receive_timeout, timeout_ms)
                    |> Keyword.put(:pool_timeout, timeout_ms)

                  # Add JSON decoding if enabled
                  req_options =
                    if json, do: Keyword.put(req_options, :decode_json, json), else: req_options

                  # Add body for POST/PUT requests if params are provided
                  req_options =
                    case method do
                      m when m in [:post, :put] ->
                        Keyword.put(req_options, :json, params)

                      _ ->
                        Keyword.put(req_options, :params, params)
                    end

                  # Execute the request
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
              end
            else
              {:error,
               Error.config_error(
                 "Req library is required for ReqTool. Add {:req, \"~> 0.5\"} to your deps.",
                 %{dependency: :req}
               )}
            end
          end

          defp resolve_request_timeout_ms(context) do
            context_timeout =
              if is_map(context) do
                Enum.find(
                  [
                    remaining_timeout_ms(Map.get(context, :__jido_exec_deadline_ms__)),
                    remaining_timeout_ms(Map.get(context, "__jido_exec_deadline_ms__")),
                    Map.get(context, :timeout),
                    Map.get(context, "timeout")
                  ],
                  fn
                    value when is_integer(value) and value >= 0 -> true
                    _ -> false
                  end
                )
              else
                nil
              end

            case context_timeout do
              value when is_integer(value) and value >= 0 ->
                value

              _ ->
                Jido.Action.Config.exec_timeout()
            end
          end

          defp remaining_timeout_ms(deadline_ms) when is_integer(deadline_ms) do
            max(deadline_ms - System.monotonic_time(:millisecond), 0)
          end

          defp remaining_timeout_ms(_), do: nil

          # Default implementation for transform_result
          @impl Jido.Tools.ReqTool
          def transform_result(result) do
            {:ok, result}
          end

          # Allow transform_result to be overridden
          defoverridable transform_result: 1

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "ReqTool", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end
end
