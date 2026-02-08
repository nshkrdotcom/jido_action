defmodule Jido.Tools.Weather.Geocode do
  @moduledoc """
  Geocodes a location string to latitude/longitude coordinates.

  Uses OpenStreetMap's Nominatim API for geocoding.
  Supports city/state, addresses, zipcodes, and other location formats.
  """

  use Jido.Action,
    name: "weather_geocode",
    description: "Convert a location string to lat,lng coordinates",
    category: "Weather",
    tags: ["weather", "location", "geocode"],
    vsn: "1.0.0",
    schema: [
      location: [
        type: :string,
        required: true,
        doc: "Location as city/state, address, zipcode, or place name"
      ]
    ]

  alias Jido.Tools.Weather.HTTP
  alias Jido.Action.Error

  @impl Jido.Action
  def run(%{location: location}, _context) do
    url = "https://nominatim.openstreetmap.org/search"

    with {:ok, response} <-
           HTTP.get(url,
             params: %{
               q: location,
               format: "json",
               limit: 1
             },
             headers: HTTP.json_headers(),
             error_prefix: "Geocoding HTTP error"
           ) do
      transform_result(response.status, response.body, location)
    end
  end

  defp transform_result(200, [result | _], _location) do
    lat = parse_coordinate(result["lat"])
    lng = parse_coordinate(result["lon"])

    {:ok,
     %{
       latitude: lat,
       longitude: lng,
       coordinates: "#{lat},#{lng}",
       display_name: result["display_name"]
     }}
  end

  defp transform_result(200, [], location) do
    {:error,
     Error.execution_error("No results found for location: #{location}", %{location: location})}
  end

  defp transform_result(status, body, _location) do
    {:error,
     Error.execution_error("Geocoding API error (#{status}): #{inspect(body)}", %{
       status: status,
       body: body
     })}
  end

  defp parse_coordinate(value) when is_binary(value) do
    {float, _} = Float.parse(value)
    Float.round(float, 4)
  end

  defp parse_coordinate(value) when is_float(value), do: Float.round(value, 4)
  defp parse_coordinate(value) when is_integer(value), do: value / 1
end
