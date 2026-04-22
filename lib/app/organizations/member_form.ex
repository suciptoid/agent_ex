defmodule App.Organizations.MemberForm do
  use Ecto.Schema

  import Ecto.Changeset

  alias App.Organizations.Membership

  @primary_key false

  embedded_schema do
    field :email, :string
    field :role, :string, default: "member"
  end

  def changeset(member_form, attrs \\ %{}) do
    member_form
    |> cast(attrs, [:email, :role])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_inclusion(:role, Membership.roles())
  end

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalize_email(email), do: email
end
