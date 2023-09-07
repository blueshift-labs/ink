defmodule Ink.Encoder do
  @moduledoc """
  Responsible for encoding any value to JSON. Uses `Jason` for the JSON
  encoding, but converts values that are not handled by `Jason` before that,
  like tuples or PIDs.
  """

  defmodule Record do
    # @enforce_keys [:time, :level, :msg, :metadata]

    @derive {Jason.Encoder, only: [:time, :level, :msg, :metadata]}
    defstruct [:time, :level, :msg, :metadata]
  end

  @doc """
  Accepts a map and recursively replaces all JSON incompatible values with JSON
  encodable values. Then converts the map to JSON.
  """
  def encode(map, config \\ %{})

  def encode(map, %{flatten_metadata: true}) do
    map
    |> encode_value()
    |> Jason.encode()
  end

  def encode(map, _config) do
    value = encode_value(map)

    %Record{
      time: value[:time],
      level: value[:level],
      msg: value[:msg],
      metadata: Map.drop(value, [:time, :level, :msg, :metadata])
    }
    |> Jason.encode()
  end

  defp encode_value(value)
       when is_pid(value) or is_port(value) or is_reference(value) or
              is_tuple(value) or is_function(value),
       do: inspect(value)

  defp encode_value(%{__struct__: _} = value) do
    value
    |> Map.from_struct()
    |> encode_value
  end

  defp encode_value(value) when is_map(value) do
    Enum.into(value, %{}, fn {k, v} ->
      {encode_value(k), encode_value(v)}
    end)
  end

  defp encode_value([]), do: []

  defp encode_value(value) when is_list(value) do
    cond do
      Keyword.keyword?(value) ->
        value
        |> Enum.into(%{})
        |> encode_value()

      true ->
        Enum.map(value, &encode_value/1)
    end
  end

  defp encode_value(value), do: value
end
