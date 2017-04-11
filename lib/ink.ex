defmodule Ink do
  use GenEvent

  def init(__MODULE__) do
    {:ok, configure(Application.get_env(:logger, Ink, []), default_options())}
  end

  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(options, state)}
  end

  def handle_event({_, gl, {Logger, _, _, _}}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  def handle_event({level, _, {Logger, message, timestamp, metadata}}, state) do
    log_message(message, level, timestamp, metadata, state)
    {:ok, state}
  end

  defp configure(options, state) do
    state
    |> Map.merge(Enum.into(options, %{}))
    |> update_secret_strings
  end

  defp log_message(message, level, timestamp, metadata, config) do
    if Logger.compare_levels(level, config.level) != :lt do
      message
      |> base_map(timestamp, level)
      |> Map.merge(process_metadata(metadata, config))
      |> Poison.encode
      |> log_json(config)
    end
  end

  defp process_metadata(metadata, config) do
    metadata
    |> filter_metadata(config)
    |> rename_metadata_fields
    |> Enum.into(%{})
  end

  defp filter_metadata(metadata, %{metadata: nil}), do: metadata
  defp filter_metadata(metadata, config) do
    metadata |> Enum.filter(fn {key, _} -> key in config.metadata end)
  end

  defp rename_metadata_fields(metadata) do
    metadata
    |> Enum.map(fn
      {:pid, value} -> {:erlang_pid, value}
      other -> other
    end)
  end

  defp log_json({:ok, json}, config) do
    json
    |> filter_secret_strings(config.secret_strings)
    |> log_to_device(config.io_device)
  end
  defp log_json(other, config) do
    if Mix.env == :dev, do: log_to_device(inspect(other), config.io_device)
  end

  defp log_to_device(msg, io_device), do: IO.puts(io_device, msg)

  defp base_map(message, timestamp, level) when is_binary(message) do
    %{message: message, timestamp: formatted_timestamp(timestamp), level: level}
  end
  defp base_map(message, timestamp, level) when is_list(message) do
    base_map(IO.iodata_to_binary(message), timestamp, level)
  end

  defp formatted_timestamp({date, {hours, minutes, seconds, milliseconds}}) do
    {date, {hours, minutes, seconds}}
    |> NaiveDateTime.from_erl!({milliseconds * 1000, 3})
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601
  end

  defp update_secret_strings(config) do
    secret_strings = config.filtered_strings
    |> Kernel.++(uri_credentials(config.filtered_uri_credentials))
    |> Enum.reject(fn s -> s == "" || is_nil(s) end)
    Map.put(config, :secret_strings, secret_strings)
  end

  defp uri_credentials(uris) do
    uris
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn uri -> uri |> URI.parse |> Map.get(:userinfo) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn userinfo -> userinfo |> String.split(":") |> List.last end)
  end

  defp filter_secret_strings(message, secret_strings) do
    Enum.reduce(secret_strings, message, fn secret, msg ->
      String.replace(msg, secret, "[FILTERED]")
    end)
  end

  defp default_options do
    %{
      level: :debug,
      filtered_strings: [],
      filtered_uri_credentials: [],
      secret_strings: [],
      io_device: :stdio,
      metadata: nil
    }
  end
end
