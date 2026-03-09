defmodule App.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: App.Vault
end
