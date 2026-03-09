defmodule App.Vault do
  use Cloak.Vault, otp_app: :app

  @impl true
  def init(config) do
    case System.get_env("ENCRYPTION_KEY") do
      nil ->
        {:ok, config}

      encoded_key ->
        ciphers = [
          default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(encoded_key)}
        ]

        {:ok, Keyword.put(config, :ciphers, ciphers)}
    end
  end
end
