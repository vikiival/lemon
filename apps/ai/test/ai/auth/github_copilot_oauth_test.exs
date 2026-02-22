defmodule Ai.Auth.GitHubCopilotOAuthTest do
  use ExUnit.Case, async: false

  alias Ai.Auth.GitHubCopilotOAuth

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "github_copilot_oauth_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)

    prev_home = System.get_env("HOME")
    prev_copilot_dir = System.get_env("GITHUB_COPILOT_CONFIG_DIR")
    prev_gh_config_dir = System.get_env("GH_CONFIG_DIR")
    prev_lemon_credentials_dir = System.get_env("LEMON_CREDENTIALS_DIR")

    System.put_env("HOME", tmp)
    System.put_env("GITHUB_COPILOT_CONFIG_DIR", Path.join(tmp, "copilot"))
    System.put_env("GH_CONFIG_DIR", Path.join(tmp, "gh"))
    System.put_env("LEMON_CREDENTIALS_DIR", Path.join(tmp, "credentials"))

    on_exit(fn ->
      if is_binary(prev_home),
        do: System.put_env("HOME", prev_home),
        else: System.delete_env("HOME")

      if is_binary(prev_copilot_dir) do
        System.put_env("GITHUB_COPILOT_CONFIG_DIR", prev_copilot_dir)
      else
        System.delete_env("GITHUB_COPILOT_CONFIG_DIR")
      end

      if is_binary(prev_gh_config_dir) do
        System.put_env("GH_CONFIG_DIR", prev_gh_config_dir)
      else
        System.delete_env("GH_CONFIG_DIR")
      end

      if is_binary(prev_lemon_credentials_dir) do
        System.put_env("LEMON_CREDENTIALS_DIR", prev_lemon_credentials_dir)
      else
        System.delete_env("LEMON_CREDENTIALS_DIR")
      end

      File.rm_rf(tmp)
    end)

    %{tmp: tmp}
  end

  test "returns nil when no credential source exists" do
    assert GitHubCopilotOAuth.resolve_access_token() == nil
  end

  test "reads oauth token from github-copilot apps.json", %{tmp: tmp} do
    copilot_dir = Path.join(tmp, "copilot")
    File.mkdir_p!(copilot_dir)

    File.write!(
      Path.join(copilot_dir, "apps.json"),
      Jason.encode!(%{
        "github.com:Iv1.x" => %{
          "oauth_token" => "copilot-token-123",
          "user" => "tester"
        }
      })
    )

    assert GitHubCopilotOAuth.resolve_access_token() == "copilot-token-123"
  end

  test "reads oauth token from gh hosts.yml when apps.json is missing", %{tmp: tmp} do
    gh_dir = Path.join(tmp, "gh")
    File.mkdir_p!(gh_dir)

    File.write!(
      Path.join(gh_dir, "hosts.yml"),
      """
      github.com:
          user: test-user
          oauth_token: gh-hosts-token
          git_protocol: https
      """
    )

    assert GitHubCopilotOAuth.resolve_access_token() == "gh-hosts-token"
  end
end
