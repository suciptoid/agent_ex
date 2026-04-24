defmodule App.Tasks.Task do
  use Ecto.Schema

  import Ecto.Changeset

  alias App.Tasks.Schedule

  @schedule_types Schedule.schedule_types()
  @every_units Schedule.every_units()

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "scheduled_tasks" do
    field :name, :string
    field :prompt, :string
    field :next_run, :utc_datetime_usec
    field :repeat, :boolean, default: false
    field :schedule_type, Ecto.Enum, values: @schedule_types, default: :once
    field :cron_expression, :string
    field :every_interval, :integer
    field :every_unit, Ecto.Enum, values: @every_units
    field :last_run_at, :utc_datetime_usec

    field :agent_ids, {:array, :binary_id}, virtual: true, default: []
    field :next_run_input, :string, virtual: true
    field :run_mode, :string, virtual: true, default: "once"

    belongs_to :organization, App.Organizations.Organization
    belongs_to :main_agent, App.Agents.Agent
    belongs_to :notification_chat_room, App.Chat.ChatRoom

    has_many :task_agents, App.Tasks.TaskAgent, foreign_key: :scheduled_task_id
    has_many :agents, through: [:task_agents, :agent]

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :name,
      :prompt,
      :next_run,
      :next_run_input,
      :run_mode,
      :repeat,
      :schedule_type,
      :cron_expression,
      :every_interval,
      :every_unit,
      :last_run_at,
      :main_agent_id,
      :notification_chat_room_id,
      :agent_ids
    ])
    |> update_change(:name, &trim_text/1)
    |> update_change(:prompt, &normalize_text/1)
    |> update_change(:cron_expression, &normalize_optional_text/1)
    |> update_change(:agent_ids, &normalize_agent_ids/1)
    |> normalize_run_mode()
    |> normalize_schedule_fields()
    |> put_next_run_from_input()
    |> validate_required([:name, :prompt, :main_agent_id])
    |> validate_length(:name, max: 120)
    |> validate_length(:prompt, max: 20_000)
    |> validate_agent_ids()
    |> validate_main_agent()
    |> validate_next_run()
    |> validate_repeat_config()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:main_agent_id)
    |> foreign_key_constraint(:notification_chat_room_id)
  end

  def schedule_types, do: @schedule_types
  def every_units, do: @every_units

  defp normalize_schedule_fields(changeset) do
    repeat? = get_field(changeset, :repeat, false)
    schedule_type = get_field(changeset, :schedule_type, :once)

    cond do
      not repeat? ->
        changeset
        |> put_change(:next_run, get_field(changeset, :next_run))
        |> put_change(:schedule_type, :once)
        |> put_change(:cron_expression, nil)
        |> put_change(:every_interval, nil)
        |> put_change(:every_unit, nil)

      schedule_type == :cron ->
        changeset
        |> put_change(:every_interval, nil)
        |> put_change(:every_unit, nil)

      schedule_type == :every ->
        put_change(changeset, :cron_expression, nil)

      true ->
        put_change(changeset, :schedule_type, :every)
    end
  end

  defp put_next_run_from_input(changeset) do
    case get_change(changeset, :next_run_input) do
      nil ->
        changeset

      value ->
        case Schedule.parse_datetime_input(value) do
          {:ok, next_run} ->
            put_change(changeset, :next_run, next_run)

          {:error, :blank} ->
            put_change(changeset, :next_run, nil)

          {:error, :invalid} ->
            add_error(changeset, :next_run_input, "must be a valid UTC datetime")
        end
    end
  end

  defp normalize_run_mode(changeset) do
    case get_change(changeset, :run_mode) do
      "once" ->
        put_change(changeset, :repeat, false)

      "repeat" ->
        put_change(changeset, :repeat, true)

      _other ->
        changeset
    end
  end

  defp validate_agent_ids(changeset) do
    case get_field(changeset, :agent_ids, []) do
      [] -> add_error(changeset, :agent_ids, "select at least one agent")
      _agent_ids -> changeset
    end
  end

  defp validate_main_agent(changeset) do
    main_agent_id = get_field(changeset, :main_agent_id)
    agent_ids = get_field(changeset, :agent_ids, [])

    cond do
      is_nil(main_agent_id) ->
        changeset

      main_agent_id in agent_ids ->
        changeset

      true ->
        add_error(changeset, :main_agent_id, "must be one of the selected agents")
    end
  end

  defp validate_next_run(changeset) do
    if get_field(changeset, :repeat, false) do
      changeset
    else
      if get_field(changeset, :next_run) do
        changeset
      else
        add_error(changeset, :next_run_input, "can't be blank")
      end
    end
  end

  defp validate_repeat_config(changeset) do
    repeat? = get_field(changeset, :repeat, false)
    schedule_type = get_field(changeset, :schedule_type, :once)

    cond do
      not repeat? ->
        changeset

      schedule_type == :cron ->
        case Schedule.valid_cron_expression?(get_field(changeset, :cron_expression)) do
          :ok ->
            changeset

          {:error, :invalid_cron_expression} ->
            add_error(changeset, :cron_expression, "is invalid")
        end

      schedule_type == :every ->
        changeset
        |> validate_required([:every_interval, :every_unit])
        |> validate_number(:every_interval, greater_than: 0)

      true ->
        add_error(changeset, :schedule_type, "must be cron or every when repeat is enabled")
    end
  end

  defp normalize_agent_ids(agent_ids) do
    agent_ids
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value

  defp normalize_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(value), do: value

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(value), do: value
end
