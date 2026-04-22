defmodule App.Repo.Migrations.AddApprovalStatusToGatewayChannels do
  use Ecto.Migration

  def change do
    alter table(:gateway_channels) do
      add :approval_status, :string, default: "approved", null: false
    end

    create index(:gateway_channels, [:approval_status])
  end
end
