defmodule App.Vault do
  use Cloak.Vault, otp_app: :app
  require Logger

  @default_key "pFpkh+qsr4lSrdMP+eHMwTAMFUWOo24LVfXkVwrUWJM="

  @impl true
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: decode_env!("CLOAK_KEY")}
      )

    {:ok, config}
  end

  defp decode_env!(var) do
    key =
      case System.get_env(var) do
        nil ->
          Logger.warning("Missing #{var} environment variable, use default key.")

          @default_key

        val when is_binary(val) ->
          val
      end

    key |> Base.decode64!()
  end
end
