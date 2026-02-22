defmodule Ai.Auth.GitHubCopilotOAuth do
  @moduledoc """
  Helpers for resolving GitHub Copilot OAuth credentials.

  This module follows the same non-interactive approach as OpenAI Codex OAuth:
  - Read token from Lemon cache (`~/.lemon/credentials/github-copilot.json`)
  - Fallback to local Copilot auth file (`~/.config/github-copilot/apps.json`)
  - Fallback to GitHub CLI auth file (`~/.config/gh/hosts.yml`)

  Lemon does not run an interactive login flow. Authenticate with a GitHub/Copilot
  client first, then Lemon will reuse discovered credentials.
  """

  require Logger

  @lemon_rel_path [".lemon", "credentials", "github-copilot.json"]

  @doc """
  Resolve a GitHub Copilot OAuth access token.

  Returns `nil` when no credential source is available.
  """
  @spec resolve_access_token() :: String.t() | nil
  def resolve_access_token do
    with {:ok, {token, source}} <- load_best_token() do
      maybe_cache_token(token, source)
      token
    else
      _ -> nil
    end
  end

  defp load_best_token do
    load_lemon_store() || load_copilot_apps_file() || load_gh_hosts_file()
  end

  defp load_lemon_store do
    path = lemon_cred_path()

    if File.exists?(path) do
      case File.read(path) do
        {:ok, raw} ->
          case Jason.decode(raw) do
            {:ok, data} when is_map(data) ->
              token =
                data["access_token"] || data["oauth_token"] || data["token"] || data["api_key"]

              if is_binary(token) and token != "" do
                {:ok, {token, :lemon_store}}
              else
                nil
              end

            _ ->
              nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp load_copilot_apps_file do
    path = Path.join(resolve_copilot_config_dir(), "apps.json")

    if File.exists?(path) do
      case File.read(path) do
        {:ok, raw} ->
          with {:ok, decoded} <- Jason.decode(raw),
               token when is_binary(token) <- extract_token_from_apps(decoded),
               true <- token != "" do
            {:ok, {token, :copilot_apps}}
          else
            _ -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp load_gh_hosts_file do
    path = Path.join(resolve_gh_config_dir(), "hosts.yml")

    if File.exists?(path) do
      case File.read(path) do
        {:ok, raw} ->
          case extract_token_from_hosts_yaml(raw) do
            token when is_binary(token) and token != "" -> {:ok, {token, :gh_hosts}}
            _ -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp extract_token_from_apps(decoded) when is_map(decoded) do
    decoded
    |> Enum.filter(fn {key, value} -> is_binary(key) and is_map(value) end)
    |> Enum.sort_by(fn {key, _value} ->
      if String.starts_with?(key, "github.com:"), do: 0, else: 1
    end)
    |> Enum.find_value(fn {_key, value} ->
      token = value["oauth_token"]
      if is_binary(token) and token != "", do: token, else: nil
    end)
  end

  defp extract_token_from_apps(_), do: nil

  defp extract_token_from_hosts_yaml(raw) when is_binary(raw) do
    lines = String.split(raw, "\n")

    {_host, token} =
      Enum.reduce(lines, {nil, nil}, fn line, {current_host, current_token} ->
        cond do
          current_token ->
            {current_host, current_token}

          host = parse_host_line(line) ->
            {host, nil}

          current_host == "github.com" ->
            oauth = parse_oauth_line(line)
            {current_host, oauth}

          true ->
            {current_host, nil}
        end
      end)

    token
  end

  defp parse_host_line(line) do
    case Regex.run(~r/^\s*([A-Za-z0-9.\-]+):\s*$/, line, capture: :all_but_first) do
      [host] -> host
      _ -> nil
    end
  end

  defp parse_oauth_line(line) do
    case Regex.run(~r/^\s*oauth_token:\s*(.+?)\s*$/, line, capture: :all_but_first) do
      [token] ->
        token
        |> String.trim()
        |> String.trim("\"")
        |> String.trim("'")

      _ ->
        nil
    end
  end

  defp maybe_cache_token(token, :lemon_store) when is_binary(token), do: :ok

  defp maybe_cache_token(token, source) when is_binary(token) do
    payload = %{
      "access_token" => token,
      "source" => to_string(source),
      "updated_at_ms" => System.system_time(:millisecond)
    }

    path = lemon_cred_path()

    with :ok <- File.mkdir_p(Path.dirname(path)),
         encoded <- Jason.encode!(payload),
         :ok <- File.write(path, encoded) do
      :ok
    else
      error ->
        Logger.debug("GitHub Copilot OAuth cache write failed: #{inspect(error)}")
        :ok
    end
  end

  defp lemon_cred_path do
    case System.get_env("LEMON_CREDENTIALS_DIR") do
      dir when is_binary(dir) and dir != "" ->
        Path.join(Path.expand(dir), "github-copilot.json")

      _ ->
        Path.join([System.user_home!() | @lemon_rel_path])
    end
  end

  defp resolve_copilot_config_dir do
    case System.get_env("GITHUB_COPILOT_CONFIG_DIR") do
      v when is_binary(v) and v != "" -> Path.expand(v)
      _ -> Path.expand("~/.config/github-copilot")
    end
  end

  defp resolve_gh_config_dir do
    case System.get_env("GH_CONFIG_DIR") do
      v when is_binary(v) and v != "" -> Path.expand(v)
      _ -> Path.expand("~/.config/gh")
    end
  end
end
