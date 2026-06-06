defmodule OledDisplay.Weather.Client do
  @moduledoc """
  Plain-HTTP weather client for wttr.in using raw :gen_tcp.

  Uses HTTP (port 80) to avoid TLS heap pressure on ESP32-C3.
  Requests a tiny pipe-delimited response: temp|humidity|condition.

  NOTE: Uses :gen_tcp directly instead of :ahttp_client because
  ahttp_client on AtomVM ESP32 can drop the body when the server
  sends Connection: close immediately after a small response.
  """

  @compile {:no_warn_undefined, [:gen_tcp]}

  require OledDisplay.Log
  alias OledDisplay.Log

  @host "wttr.in"
  @recv_timeout_ms 8_000

  def fetch(%{lat: lat, lon: lon, units: units}) do
    try do
      do_fetch(%{lat: lat, lon: lon, units: units})
    catch
      class, reason ->
        Log.debugf("Weather.Client", "caught ~p ~p", [class, reason])
        {:error, {class, reason}}
    end
  end

  defp do_fetch(%{lat: lat, lon: lon, units: units}) do
    path = "/#{lat},#{lon}?format=%t|%h|%C"
    host_charlist = :erlang.binary_to_list(@host)

    Log.debug("Weather.Client", "fetching #{@host}#{path}")

    with {:ok, sock} <- :gen_tcp.connect(host_charlist, 80, [{:active, false}, :binary]) do
      req =
        "GET #{path} HTTP/1.1\r\n" <>
          "Host: #{@host}\r\n" <>
          "Connection: close\r\n" <>
          "\r\n"

      :ok = :gen_tcp.send(sock, req)
      Log.debug("Weather.Client", "request sent, receiving...")

      case recv_all(sock, <<>>) do
        {:ok, raw} ->
          :gen_tcp.close(sock)

          case extract_body(raw) do
            {:ok, body} ->
              Log.debugf("Weather.Client", "body=~p", [body])
              parse(body, units)

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          :gen_tcp.close(sock)
          {:error, reason}
      end
    else
      {:error, reason} ->
        Log.debugf("Weather.Client", "connect error ~p", [reason])
        {:error, reason}
    end
  end

  # ── TCP read ────────────────────────────────────────────────────

  defp recv_all(sock, acc) do
    case :gen_tcp.recv(sock, 0, @recv_timeout_ms) do
      {:ok, data} ->
        recv_all(sock, <<acc::binary, data::binary>>)

      {:error, :closed} ->
        {:ok, acc}

      {:error, :timeout} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── HTTP body extraction ───────────────────────────────────────

  defp extract_body(raw) do
    case :binary.match(raw, "\r\n\r\n") do
      :nomatch ->
        {:error, :no_body_separator}

      {pos, 4} ->
        <<_headers::binary-size(pos + 4), body::binary>> = raw
        {:ok, body}
    end
  end

  # ── Parsing ──────────────────────────────────────────────────────

  defp parse(body, units) do
    # Expected: "+22°C|65%|Partly cloudy"  (may have trailing whitespace)
    # wttr.in returns Celsius by default; we parse the number and convert
    # if the user asked for Fahrenheit.
    parts = split_pipes(body, [])

    case parts do
      [temp_str, hum_str, cond_str | _] ->
        temp_c = parse_temp(temp_str)
        temp = if units == :fahrenheit, do: c_to_f(temp_c), else: temp_c
        humidity = parse_humidity(hum_str)
        icon = condition_to_icon(cond_str)

        {:ok,
         %{
           temp: temp,
           humidity: humidity,
           icon: icon,
           is_day: 1,
           fetched_at: :erlang.system_time(:millisecond)
         }}

      _other ->
        Log.debugf("Weather.Client", "parse failed for body=~p", [body])
        {:error, :parse_failed}
    end
  end

  defp split_pipes(<<>>, acc), do: Enum.reverse(acc)

  defp split_pipes(bin, acc) do
    case :binary.match(bin, "|") do
      :nomatch ->
        Enum.reverse([bin | acc])

      {pos, 1} ->
        <<part::binary-size(pos), _, rest::binary>> = bin
        split_pipes(rest, [part | acc])
    end
  end

  defp parse_temp(<<c, rest::binary>>) when c == ?+ or c == ?- do
    sign = if c == ?-, do: -1, else: 1
    sign * parse_number(rest, 0)
  end

  defp parse_temp(<<_, _::binary>> = str) do
    parse_number(str, 0)
  end

  defp parse_temp(_), do: 0

  defp parse_number(<<c, rest::binary>>, acc) when c >= ?0 and c <= ?9 do
    parse_number(rest, acc * 10 + (c - ?0))
  end

  defp parse_number(_, acc), do: acc

  defp parse_humidity(<<c, rest::binary>>) when c >= ?0 and c <= ?9 do
    parse_number(rest, c - ?0)
  end

  defp parse_humidity(_), do: 0

  defp c_to_f(c), do: :erlang.round(c * 9 / 5 + 32)

  # ── Condition → icon mapping ────────────────────────────────────

  defp condition_to_icon(str) do
    s = to_lower(str)

    cond do
      contains?(s, "clear") or contains?(s, "sunny") ->
        :sun

      contains?(s, "partly cloudy") ->
        :cloud_sun

      contains?(s, "cloud") or contains?(s, "overcast") or contains?(s, "fog") or
          contains?(s, "mist") ->
        :cloud

      contains?(s, "heavy rain") or contains?(s, "torrential") ->
        :rain2

      contains?(s, "rain") or contains?(s, "drizzle") or contains?(s, "sleet") ->
        :rain1

      contains?(s, "thunder") or contains?(s, "storm") ->
        :rain_lightning

      contains?(s, "snow") or contains?(s, "blizzard") or contains?(s, "ice") ->
        :snow

      contains?(s, "wind") ->
        :wind

      true ->
        :cloud
    end
  end

  defp contains?(haystack, needle) do
    :binary.match(haystack, needle) != :nomatch
  end

  defp to_lower(<<c, rest::binary>>) when c >= ?A and c <= ?Z,
    do: <<c + 32, to_lower(rest)::binary>>

  defp to_lower(<<c, rest::binary>>),
    do: <<c, to_lower(rest)::binary>>

  defp to_lower(<<>>), do: <<>>
end
