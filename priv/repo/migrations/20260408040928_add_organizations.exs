defmodule App.Repo.Migrations.AddOrganizations do
  use Ecto.Migration

  def up do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :settings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:organization_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:organization_memberships, [:user_id])

    create unique_index(:organization_memberships, [:organization_id, :user_id],
             name: :organization_memberships_org_user_index
           )

    create unique_index(:organization_memberships, [:organization_id],
             where: "role = 'owner'",
             name: :organization_memberships_single_owner_index
           )

    alter table(:providers) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:tools) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:agents) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:chat_rooms) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    flush()

    backfill_organizations()

    drop index(:providers, [:user_id])
    drop index(:providers, [:user_id, :provider])
    drop index(:tools, [:user_id])
    drop index(:agents, [:user_id])
    drop index(:chat_rooms, [:user_id])
    drop index(:tools, [:user_id, :name], name: :tools_user_id_name_index)

    alter table(:providers) do
      modify :organization_id, :binary_id, null: false
      remove :user_id
    end

    alter table(:tools) do
      modify :organization_id, :binary_id, null: false
      remove :user_id
    end

    alter table(:agents) do
      modify :organization_id, :binary_id, null: false
      remove :user_id
    end

    alter table(:chat_rooms) do
      modify :organization_id, :binary_id, null: false
      remove :user_id
    end

    create index(:providers, [:organization_id])
    create index(:providers, [:organization_id, :provider])
    create index(:tools, [:organization_id])
    create index(:agents, [:organization_id])
    create index(:chat_rooms, [:organization_id])

    create unique_index(:tools, [:organization_id, :name],
             name: :tools_organization_id_name_index
           )
  end

  def down do
    alter table(:providers) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:tools) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:agents) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:chat_rooms) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    flush()

    restore_user_scopes()

    drop index(:providers, [:organization_id])
    drop index(:providers, [:organization_id, :provider])
    drop index(:tools, [:organization_id])
    drop index(:agents, [:organization_id])
    drop index(:chat_rooms, [:organization_id])
    drop index(:tools, [:organization_id, :name], name: :tools_organization_id_name_index)

    alter table(:providers) do
      modify :user_id, :binary_id, null: false
      remove :organization_id
    end

    alter table(:tools) do
      modify :user_id, :binary_id, null: false
      remove :organization_id
    end

    alter table(:agents) do
      modify :user_id, :binary_id, null: false
      remove :organization_id
    end

    alter table(:chat_rooms) do
      modify :user_id, :binary_id, null: false
      remove :organization_id
    end

    create index(:providers, [:user_id])
    create index(:providers, [:user_id, :provider])
    create index(:tools, [:user_id])
    create index(:agents, [:user_id])
    create index(:chat_rooms, [:user_id])
    create unique_index(:tools, [:user_id, :name], name: :tools_user_id_name_index)

    drop table(:organization_memberships)
    drop table(:organizations)
  end

  defp backfill_organizations do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    organizations =
      repo().query!("SELECT id, email FROM users ORDER BY inserted_at ASC").rows
      |> Enum.map(fn [user_id, email] ->
        %{
          organization_id: user_id,
          user_id: user_id,
          organization: %{
            id: user_id,
            name: organization_name(email),
            settings: %{},
            inserted_at: now,
            updated_at: now
          },
          membership: %{
            id: user_id,
            organization_id: user_id,
            user_id: user_id,
            role: "owner",
            inserted_at: now,
            updated_at: now
          }
        }
      end)

    repo().insert_all("organizations", Enum.map(organizations, & &1.organization))
    repo().insert_all("organization_memberships", Enum.map(organizations, & &1.membership))

    repo().query!(
      """
      UPDATE providers AS providers
      SET organization_id = memberships.organization_id
      FROM organization_memberships AS memberships
      WHERE memberships.role = 'owner' AND memberships.user_id = providers.user_id
      """,
      []
    )

    repo().query!(
      """
      UPDATE tools AS tools
      SET organization_id = memberships.organization_id
      FROM organization_memberships AS memberships
      WHERE memberships.role = 'owner' AND memberships.user_id = tools.user_id
      """,
      []
    )

    repo().query!(
      """
      UPDATE agents AS agents
      SET organization_id = memberships.organization_id
      FROM organization_memberships AS memberships
      WHERE memberships.role = 'owner' AND memberships.user_id = agents.user_id
      """,
      []
    )

    repo().query!(
      """
      UPDATE chat_rooms AS chat_rooms
      SET organization_id = memberships.organization_id
      FROM organization_memberships AS memberships
      WHERE memberships.role = 'owner' AND memberships.user_id = chat_rooms.user_id
      """,
      []
    )
  end

  defp restore_user_scopes do
    repo().query!(
      """
      UPDATE providers AS providers
      SET user_id = memberships.user_id
      FROM organization_memberships AS memberships
      WHERE memberships.role = 'owner' AND memberships.organization_id = providers.organization_id
      """,
      []
    )

    repo().query!(
      """
      UPDATE tools AS tools
      SET user_id = memberships.user_id
      FROM organization_memberships AS memberships
      WHERE memberships.role = 'owner' AND memberships.organization_id = tools.organization_id
      """,
      []
    )

    repo().query!(
      """
      UPDATE agents AS agents
      SET user_id = memberships.user_id
      FROM organization_memberships AS memberships
      WHERE memberships.role = 'owner' AND memberships.organization_id = agents.organization_id
      """,
      []
    )

    repo().query!(
      """
      UPDATE chat_rooms AS chat_rooms
      SET user_id = memberships.user_id
      FROM organization_memberships AS memberships
      WHERE memberships.role = 'owner' AND memberships.organization_id = chat_rooms.organization_id
      """,
      []
    )
  end

  defp organization_name(email) when is_binary(email) do
    label =
      email
      |> String.split("@", parts: 2)
      |> List.first()
      |> to_string()
      |> String.replace(~r/[-_.]+/, " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

    if label == "", do: "My Organization", else: "#{label}'s Organization"
  end
end
