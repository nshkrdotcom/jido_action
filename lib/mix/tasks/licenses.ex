defmodule Mix.Tasks.Licenses do
  @shortdoc "Check dependency licenses"
  @moduledoc """
  Mix task to check dependency licenses against an allowlist.

  ## Usage

      mix licenses                # List all dependency licenses
      mix licenses --check        # Check licenses against allowlist (fails on forbidden)
      mix licenses --report       # Generate detailed license report

  ## Configuration

  Configure allowed and forbidden licenses in your mix.exs:

      def project do
        [
          # ... other config
          license_check: [
            allowed: ~w[MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC],
            forbidden: ~w[GPL-2.0 GPL-3.0 AGPL-3.0 LGPL-2.1 LGPL-3.0],
            unknown_action: :warn  # :warn, :error, or :allow
          ]
        ]
      end
  """

  use Mix.Task

  @recursive true

  @default_config [
    allowed: ~w[MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC MPL-2.0],
    forbidden: ~w[GPL-2.0 GPL-3.0 AGPL-3.0 LGPL-2.1 LGPL-3.0 BUSL-1.1],
    unknown_action: :warn
  ]

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [check: :boolean, report: :boolean, verbose: :boolean],
        aliases: [c: :check, r: :report, v: :verbose]
      )

    Mix.Task.run("deps.loadpaths", args)

    config = get_config()
    deps_info = get_dependencies_info()

    cond do
      opts[:report] -> generate_report(deps_info, config)
      opts[:check] -> check_licenses(deps_info, config)
      true -> list_licenses(deps_info, opts[:verbose] || false)
    end
  end

  defp get_config do
    Mix.Project.config()
    |> Keyword.get(:license_check, [])
    |> Keyword.merge(@default_config, fn _k, v1, _v2 -> v1 end)
  end

  defp get_dependencies_info do
    deps = Mix.Project.config()[:deps] || []

    deps
    |> Enum.flat_map(fn dep_spec ->
      {app, _req, opts} = parse_dep_spec(dep_spec)

      case get_package_info(app, opts) do
        {:ok, info} -> [{app, info, opts}]
        {:error, _} -> [{app, %{licenses: ["Unknown"], source: :unknown}, opts}]
      end
    end)
  end

  defp parse_dep_spec({app, req}) when is_binary(req) or is_list(req) do
    {app, req, []}
  end

  defp parse_dep_spec({app, opts}) when is_list(opts) do
    {app, nil, opts}
  end

  defp parse_dep_spec({app, req, opts}) do
    {app, req, opts}
  end

  defp get_package_info(app, opts) do
    # For known packages, provide hardcoded license info as fallback
    case get_known_license(app) do
      nil ->
        # Try to read local license files
        case get_local_license_info(app, opts) do
          {:ok, info} -> {:ok, info}
          {:error, _} -> {:error, :no_license_found}
        end

      licenses ->
        {:ok, %{licenses: licenses, source: :known}}
    end
  end

  defp get_local_license_info(app, opts) do
    # Try to find license files in the dependency
    dep_path =
      if opts[:path] do
        opts[:path]
      else
        Path.join([Mix.Project.deps_path(), to_string(app)])
      end

    license_files = [
      "LICENSE",
      "LICENSE.md",
      "LICENSE.txt",
      "COPYING",
      "COPYRIGHT"
    ]

    licenses =
      license_files
      |> Enum.find_value([], fn file ->
        file_path = Path.join(dep_path, file)

        if File.exists?(file_path) do
          content = File.read!(file_path)
          detect_license_from_content(content)
        end
      end)

    case licenses do
      [] -> {:error, :no_license_found}
      licenses -> {:ok, %{licenses: licenses, source: :file}}
    end
  end

  defp detect_license_from_content(content) do
    content = String.downcase(content)

    cond do
      String.contains?(content, "mit license") ->
        ["MIT"]

      String.contains?(content, "apache license") and String.contains?(content, "version 2.0") ->
        ["Apache-2.0"]

      String.contains?(content, "bsd") ->
        ["BSD-3-Clause"]

      String.contains?(content, "gnu general public license") and
          String.contains?(content, "version 3") ->
        ["GPL-3.0"]

      String.contains?(content, "gnu general public license") and
          String.contains?(content, "version 2") ->
        ["GPL-2.0"]

      String.contains?(content, "gnu lesser general public license") ->
        ["LGPL-3.0"]

      String.contains?(content, "gnu affero general public license") ->
        ["AGPL-3.0"]

      String.contains?(content, "mozilla public license") ->
        ["MPL-2.0"]

      String.contains?(content, "isc license") ->
        ["ISC"]

      true ->
        ["Unknown"]
    end
  end

  # Hardcoded license information for common Elixir packages
  defp get_known_license(app) do
    known_licenses = %{
      # Elixir ecosystem
      jason: ["Apache-2.0"],
      poison: ["Unlicense"],
      phoenix: ["MIT"],
      ecto: ["Apache-2.0"],
      plug: ["Apache-2.0"],
      cowboy: ["ISC"],
      ranch: ["ISC"],
      hackney: ["Apache-2.0"],
      httpoison: ["MIT"],
      req: ["Apache-2.0"],
      tesla: ["MIT"],
      finch: ["MIT"],
      mint: ["Apache-2.0"],
      nimble_options: ["Apache-2.0"],
      nimble_parsec: ["Apache-2.0"],
      nimble_pool: ["Apache-2.0"],
      telemetry: ["Apache-2.0"],
      telemetry_metrics: ["Apache-2.0"],
      typed_struct: ["MIT"],
      excoveralls: ["MIT"],
      credo: ["MIT"],
      dialyxir: ["Apache-2.0"],
      ex_doc: ["Apache-2.0"],
      ex_dbug: ["MIT"],
      mix_audit: ["MIT"],
      mix_test_watch: ["MIT"],
      expublish: ["MIT"],
      doctor: ["MIT"],
      mimic: ["Apache-2.0"],
      stream_data: ["Apache-2.0"],
      private: ["MIT"],
      splode: ["MIT"],
      uniq: ["Apache-2.0"],
      abacus: ["MIT"],
      libgraph: ["MIT"],
      tentacat: ["MIT"],
      weather: ["MIT"]
    }

    Map.get(known_licenses, app)
  end

  defp list_licenses(deps_info, verbose) do
    Mix.shell().info("Dependency Licenses:")
    Mix.shell().info("===================")

    Enum.each(deps_info, fn {app, info, _opts} ->
      licenses = Enum.join(info.licenses, ", ")
      source_info = if verbose, do: " (#{info.source})", else: ""
      Mix.shell().info("#{app}: #{licenses}#{source_info}")
    end)

    total = length(deps_info)
    Mix.shell().info("\\nTotal dependencies: #{total}")
  end

  defp check_licenses(deps_info, config) do
    allowed = config[:allowed]
    forbidden = config[:forbidden]
    unknown_action = config[:unknown_action]

    {violations, warnings} =
      Enum.reduce(deps_info, {[], []}, fn {app, info, _opts}, {violations, warnings} ->
        case categorize_licenses(info.licenses, allowed, forbidden) do
          :allowed ->
            {violations, warnings}

          :forbidden ->
            {[{app, info.licenses, :forbidden} | violations], warnings}

          :unknown ->
            case unknown_action do
              :error -> {[{app, info.licenses, :unknown} | violations], warnings}
              :warn -> {violations, [{app, info.licenses, :unknown} | warnings]}
              :allow -> {violations, warnings}
            end
        end
      end)

    if !Enum.empty?(warnings) do
      Mix.shell().info("License Warnings:")

      Enum.each(warnings, fn {app, licenses, reason} ->
        Mix.shell().info("  #{app}: #{Enum.join(licenses, ", ")} (#{reason})")
      end)

      Mix.shell().info("")
    end

    if Enum.empty?(violations) do
      Mix.shell().info("✅ All dependency licenses are compliant")
      :ok
    else
      Mix.shell().error("❌ License violations found:")

      Enum.each(violations, fn {app, licenses, reason} ->
        Mix.shell().error("  #{app}: #{Enum.join(licenses, ", ")} (#{reason})")
      end)

      Mix.shell().error("")
      Mix.shell().error("License check failed! #{length(violations)} violation(s) found.")
      System.halt(1)
    end
  end

  defp generate_report(deps_info, config) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    report = %{
      timestamp: timestamp,
      total_dependencies: length(deps_info),
      config: config,
      dependencies:
        Enum.map(deps_info, fn {app, info, _opts} ->
          %{
            name: to_string(app),
            licenses: info.licenses,
            source: info.source,
            status: categorize_licenses(info.licenses, config[:allowed], config[:forbidden])
          }
        end)
    }

    report_path = "license_report.json"
    File.write!(report_path, Jason.encode!(report, pretty: true))
    Mix.shell().info("License report generated: #{report_path}")
  end

  defp categorize_licenses(licenses, allowed, forbidden) do
    cond do
      Enum.any?(licenses, &(&1 in forbidden)) -> :forbidden
      Enum.all?(licenses, &(&1 in allowed)) -> :allowed
      true -> :unknown
    end
  end
end
