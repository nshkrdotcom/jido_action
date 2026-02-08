defmodule Jido.Tools.Weather.CurrentConditions do
  @moduledoc """
  Gets current weather conditions from nearby NWS observation stations.

  First gets the list of observation stations for a location, then fetches
  the latest conditions from the nearest station using ReqTool architecture.
  """

  use Jido.Action,
    name: "weather_current_conditions",
    description: "Get current weather conditions from nearest NWS observation station",
    category: "Weather",
    tags: ["weather", "current", "conditions", "nws"],
    vsn: "1.0.0",
    schema: [
      observation_stations_url: [
        type: :string,
        required: true,
        doc: "NWS observation stations URL from LocationToGrid action"
      ]
    ]

  alias Jido.Action.Error
  alias Jido.Tools.Weather.HTTP

  @impl Jido.Action
  def run(params, context) do
    with {:ok, stations} <- get_observation_stations(params[:observation_stations_url], context) do
      get_current_conditions(List.first(stations), context)
    end
  end

  defp get_observation_stations(stations_url, context) do
    with {:ok, response} <-
           HTTP.get(stations_url,
             headers: HTTP.geojson_headers(),
             error_prefix: "HTTP error getting stations",
             context: context
           ) do
      parse_observation_stations_response(response)
    end
  end

  defp get_current_conditions(%{url: station_url}, context) do
    observations_url = "#{station_url}/observations/latest"

    with {:ok, response} <-
           HTTP.get(observations_url,
             headers: HTTP.geojson_headers(),
             error_prefix: "HTTP error getting conditions",
             context: context
           ) do
      case response do
        %{status: 200, body: body} ->
          props = body["properties"]

          conditions = %{
            station: props["station"],
            timestamp: props["timestamp"],
            temperature: format_measurement(props["temperature"]),
            dewpoint: format_measurement(props["dewpoint"]),
            wind_direction: format_measurement(props["windDirection"]),
            wind_speed: format_measurement(props["windSpeed"]),
            wind_gust: format_measurement(props["windGust"]),
            barometric_pressure: format_measurement(props["barometricPressure"]),
            sea_level_pressure: format_measurement(props["seaLevelPressure"]),
            visibility: format_measurement(props["visibility"]),
            max_temperature_last_24_hours: format_measurement(props["maxTemperatureLast24Hours"]),
            min_temperature_last_24_hours: format_measurement(props["minTemperatureLast24Hours"]),
            precipitation_last_hour: format_measurement(props["precipitationLastHour"]),
            precipitation_last_3_hours: format_measurement(props["precipitationLast3Hours"]),
            precipitation_last_6_hours: format_measurement(props["precipitationLast6Hours"]),
            relative_humidity: format_measurement(props["relativeHumidity"]),
            wind_chill: format_measurement(props["windChill"]),
            heat_index: format_measurement(props["heatIndex"]),
            cloud_layers: props["cloudLayers"],
            text_description: props["textDescription"]
          }

          {:ok, conditions}

        %{status: status, body: body} ->
          HTTP.status_error("Failed to get current conditions", status, body)
      end
    end
  end

  defp get_current_conditions(nil, _context) do
    {:error, Error.execution_error("No observation stations available")}
  end

  defp parse_observation_stations_response(%{status: 200, body: body}) do
    stations = Enum.map(body["features"], &station_from_feature/1)
    {:ok, stations}
  end

  defp parse_observation_stations_response(%{status: status, body: body}) do
    HTTP.status_error("Failed to get observation stations", status, body)
  end

  defp station_from_feature(feature) do
    %{
      id: feature["properties"]["stationIdentifier"],
      name: feature["properties"]["name"],
      url: feature["id"]
    }
  end

  defp format_measurement(%{"value" => nil}), do: nil

  defp format_measurement(%{"value" => value, "unitCode" => unit_code}) do
    %{value: value, unit: parse_unit_code(unit_code)}
  end

  defp format_measurement(nil), do: nil

  defp parse_unit_code("wmoUnit:" <> unit), do: unit
  defp parse_unit_code(unit), do: unit
end
