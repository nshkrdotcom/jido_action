defmodule JidoTest.Tools.Weather.ByLocationTest do
  use JidoTest.ActionCase, async: false

  import Mimic

  alias Jido.Action.Error
  alias Jido.Tools.Weather.ByLocation

  setup do
    Mimic.copy(Jido.Exec)
    :ok
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  test "builds text output with default periods and detailed forecast conversion" do
    grid_info = %{
      location: "30.2672,-97.7431",
      city: "Austin",
      state: "TX",
      timezone: "America/Chicago",
      grid: %{office: "EWX", grid_x: 1, grid_y: 2},
      urls: %{forecast: "https://api.weather.gov/gridpoints/EWX/1,2/forecast"}
    }

    forecast_data = %{
      updated: "2026-02-08T00:00:00Z",
      periods: [
        %{
          name: "Today",
          temperature: 70,
          temperature_unit: "F",
          wind_speed: "5 mph",
          wind_direction: "N",
          short_forecast: "Sunny",
          detailed_forecast: "Clear skies all day."
        }
      ]
    }

    stub(Jido.Exec, :run, fn
      Jido.Tools.Weather.LocationToGrid, %{location: "30.2672,-97.7431"}, %{}, [max_retries: 0] ->
        {:ok, grid_info}

      Jido.Tools.Weather.Forecast,
      %{
        forecast_url: "https://api.weather.gov/gridpoints/EWX/1,2/forecast",
        periods: 7,
        format: :detailed
      },
      %{},
      [max_retries: 0] ->
        {:ok, forecast_data}
    end)

    assert {:ok, result} = ByLocation.run(%{location: "30.2672,-97.7431", format: :text}, %{})
    assert result.location.state == "TX"
    assert is_binary(result.forecast)
    assert result.forecast =~ "Wind: 5 mph N"
    assert result.forecast =~ "Details: Clear skies all day."
    refute Map.has_key?(result, :grid_info)
  end

  test "includes grid info when include_location_info is true" do
    grid_info = %{
      location: "35.0000,-80.0000",
      city: "Charlotte",
      state: "NC",
      timezone: "America/New_York",
      grid: %{office: "GSP", grid_x: 10, grid_y: 12},
      urls: %{forecast: "https://api.weather.gov/gridpoints/GSP/10,12/forecast"}
    }

    forecast_data = %{
      updated: "2026-02-08T00:00:00Z",
      periods: [%{name: "Tonight"}]
    }

    stub(Jido.Exec, :run, fn
      Jido.Tools.Weather.LocationToGrid, %{location: "35.0000,-80.0000"}, %{}, [max_retries: 0] ->
        {:ok, grid_info}

      Jido.Tools.Weather.Forecast,
      %{
        forecast_url: "https://api.weather.gov/gridpoints/GSP/10,12/forecast",
        periods: 3,
        format: :summary
      },
      %{},
      [max_retries: 0] ->
        {:ok, forecast_data}
    end)

    assert {:ok, result} =
             ByLocation.run(
               %{
                 location: "35.0000,-80.0000",
                 periods: 3,
                 format: :summary,
                 include_location_info: true
               },
               %{}
             )

    assert result.location.state == "NC"
    assert result.grid_info == %{office: "GSP", grid_x: 10, grid_y: 12}
  end

  test "wraps grid-info failures with contextual error message" do
    expect(Jido.Exec, :run, fn
      Jido.Tools.Weather.LocationToGrid, %{location: "bad"}, %{}, [max_retries: 0] ->
        {:error, Error.execution_error("nws down")}
    end)

    assert {:error, %Error.ExecutionFailureError{} = error} =
             ByLocation.run(%{location: "bad"}, %{})

    assert error.message =~ "Failed to get grid info"
  end

  test "wraps non-exception forecast failures with inspect format" do
    grid_info = %{
      location: "45.0000,-122.0000",
      city: "Portland",
      state: "OR",
      timezone: "America/Los_Angeles",
      grid: %{office: "PQR", grid_x: 5, grid_y: 7},
      urls: %{forecast: "https://api.weather.gov/gridpoints/PQR/5,7/forecast"}
    }

    stub(Jido.Exec, :run, fn
      Jido.Tools.Weather.LocationToGrid,
      %{location: "45.0000,-122.0000"},
      %{},
      [max_retries: 0] ->
        {:ok, grid_info}

      Jido.Tools.Weather.Forecast,
      %{
        forecast_url: "https://api.weather.gov/gridpoints/PQR/5,7/forecast",
        periods: 7,
        format: :summary
      },
      %{},
      [max_retries: 0] ->
        {:error, :forecast_down}
    end)

    assert {:error, %Error.ExecutionFailureError{} = error} =
             ByLocation.run(%{location: "45.0000,-122.0000", format: :summary}, %{})

    assert error.message =~ "Failed to get forecast"
    assert error.message =~ ":forecast_down"
  end
end
