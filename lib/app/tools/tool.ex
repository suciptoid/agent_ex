defmodule App.Tools.Tool do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @tool_sources ~w(llm fixed)
  @param_types ~w(string integer number boolean)
  @http_methods ~w(get post)

  schema "tools" do
    field :name, :string
    field :description, :string
    field :kind, :string, default: "http"
    field :endpoint, :string
    field :http_method, :string, default: "get"
    field :parameter_definitions, :map, default: %{"items" => []}
    field :static_headers, App.Encrypted.Map

    field :param_rows, {:array, :map}, virtual: true, default: []
    field :header_rows, {:array, :map}, virtual: true, default: []

    belongs_to :organization, App.Organizations.Organization

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(tool, attrs) do
    tool
    |> cast(attrs, [
      :name,
      :description,
      :endpoint,
      :http_method,
      :param_rows,
      :header_rows
    ])
    |> put_change(:kind, "http")
    |> update_change(:name, &trim_text/1)
    |> update_change(:description, &trim_text/1)
    |> update_change(:endpoint, &trim_text/1)
    |> update_change(:http_method, &normalize_http_method/1)
    |> update_change(:param_rows, &normalize_param_rows/1)
    |> update_change(:header_rows, &normalize_header_rows/1)
    |> validate_required([:name, :description, :endpoint, :http_method])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 500)
    |> validate_change(:name, &validate_tool_name/2)
    |> validate_format(:endpoint, ~r/^https?:\/\/\S+$/, message: "must be a valid http(s) URL")
    |> validate_inclusion(:http_method, @http_methods)
    |> validate_param_rows()
    |> validate_header_rows()
    |> validate_endpoint_placeholders()
    |> put_parameter_definitions()
    |> put_static_headers()
    |> unique_constraint(:name, name: :tools_organization_id_name_index)
    |> foreign_key_constraint(:organization_id)
  end

  def param_types, do: @param_types
  def tool_sources, do: @tool_sources
  def http_methods, do: @http_methods

  def prepare_for_form(%__MODULE__{} = tool) do
    param_rows =
      tool
      |> parameter_items()
      |> Enum.map(fn item ->
        %{
          "name" => Map.get(item, "name", ""),
          "type" => Map.get(item, "type", "string"),
          "source" => Map.get(item, "source", "llm"),
          "value" => stringify_value(Map.get(item, "value"))
        }
      end)

    header_rows =
      tool.static_headers
      |> normalize_map()
      |> Enum.map(fn {key, value} ->
        %{"key" => key, "value" => stringify_value(value)}
      end)

    %{
      tool
      | param_rows: if(param_rows == [], do: [blank_param_row()], else: param_rows),
        header_rows: if(header_rows == [], do: [blank_header_row()], else: header_rows)
    }
  end

  def blank_param_row do
    %{"name" => "", "type" => "string", "source" => "llm", "value" => ""}
  end

  def blank_header_row do
    %{"key" => "", "value" => ""}
  end

  def parameter_items(%__MODULE__{} = tool) do
    tool.parameter_definitions
    |> normalize_map()
    |> Map.get("items", [])
    |> List.wrap()
    |> Enum.map(&normalize_map/1)
  end

  def static_param_items(%__MODULE__{} = tool) do
    parameter_items(tool)
    |> Enum.filter(&(Map.get(&1, "source") == "fixed"))
  end

  def runtime_param_items(%__MODULE__{} = tool) do
    parameter_items(tool)
    |> Enum.filter(&(Map.get(&1, "source") == "llm"))
  end

  def template_placeholders(%__MODULE__{} = tool) do
    Regex.scan(~r/\{([A-Za-z_][A-Za-z0-9_]*)\}/, tool.endpoint || "", capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp validate_tool_name(:name, value) do
    if App.LLM.Tool.valid_name?(value) do
      []
    else
      [name: "must be a valid tool identifier"]
    end
  end

  defp validate_param_rows(changeset) do
    rows = get_field(changeset, :param_rows, [])

    rows
    |> Enum.with_index()
    |> Enum.reduce(changeset, fn {row, index}, acc ->
      row = normalize_map(row)
      name = Map.get(row, "name", "")
      type = Map.get(row, "type", "")
      source = Map.get(row, "source", "")
      value = Map.get(row, "value")

      cond do
        row_blank?(row, ["name", "value"]) ->
          acc

        name == "" ->
          add_error(acc, :param_rows, "row #{index + 1}: name is required")

        not valid_identifier?(name) ->
          add_error(
            acc,
            :param_rows,
            "row #{index + 1}: name must use letters, numbers, and underscores"
          )

        type not in @param_types ->
          add_error(acc, :param_rows, "row #{index + 1}: type is invalid")

        source not in @tool_sources ->
          add_error(acc, :param_rows, "row #{index + 1}: source is invalid")

        source == "fixed" and blank?(value) ->
          add_error(acc, :param_rows, "row #{index + 1}: fixed values are required")

        true ->
          acc
      end
    end)
    |> validate_unique_param_names(rows)
  end

  defp validate_unique_param_names(changeset, rows) do
    names =
      rows
      |> Enum.map(&normalize_map/1)
      |> Enum.map(&Map.get(&1, "name", ""))
      |> Enum.reject(&(&1 == ""))

    if length(names) == length(Enum.uniq(names)) do
      changeset
    else
      add_error(changeset, :param_rows, "parameter names must be unique")
    end
  end

  defp validate_header_rows(changeset) do
    rows = get_field(changeset, :header_rows, [])

    rows
    |> Enum.with_index()
    |> Enum.reduce(changeset, fn {row, index}, acc ->
      row = normalize_map(row)
      key = Map.get(row, "key", "")
      value = Map.get(row, "value")

      cond do
        row_blank?(row, ["key", "value"]) ->
          acc

        key == "" ->
          add_error(acc, :header_rows, "row #{index + 1}: header key is required")

        blank?(value) ->
          add_error(acc, :header_rows, "row #{index + 1}: header value is required")

        true ->
          acc
      end
    end)
    |> validate_unique_header_keys(rows)
  end

  defp validate_unique_header_keys(changeset, rows) do
    keys =
      rows
      |> Enum.map(&normalize_map/1)
      |> Enum.map(&Map.get(&1, "key", ""))
      |> Enum.reject(&(&1 == ""))

    if length(keys) == length(Enum.uniq(keys)) do
      changeset
    else
      add_error(changeset, :header_rows, "header keys must be unique")
    end
  end

  defp validate_endpoint_placeholders(changeset) do
    placeholder_names =
      changeset
      |> get_field(:endpoint)
      |> to_string()
      |> then(&Regex.scan(~r/\{([A-Za-z_][A-Za-z0-9_]*)\}/, &1, capture: :all_but_first))
      |> List.flatten()
      |> Enum.uniq()

    param_names =
      changeset
      |> get_field(:param_rows, [])
      |> Enum.map(&normalize_map/1)
      |> Enum.map(&Map.get(&1, "name", ""))
      |> Enum.reject(&(&1 == ""))

    missing_names = Enum.reject(placeholder_names, &(&1 in param_names))

    if missing_names == [] do
      changeset
    else
      add_error(
        changeset,
        :endpoint,
        "template placeholders must match parameter names: #{Enum.join(missing_names, ", ")}"
      )
    end
  end

  defp put_parameter_definitions(changeset) do
    items =
      changeset
      |> get_field(:param_rows, [])
      |> Enum.map(&normalize_map/1)
      |> Enum.reject(&row_blank?(&1, ["name", "value"]))
      |> Enum.map(fn row ->
        %{
          "name" => Map.fetch!(row, "name"),
          "type" => Map.fetch!(row, "type"),
          "source" => Map.fetch!(row, "source"),
          "value" => cast_fixed_value(row)
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
      end)

    put_change(changeset, :parameter_definitions, %{"items" => items})
  end

  defp put_static_headers(changeset) do
    headers =
      changeset
      |> get_field(:header_rows, [])
      |> Enum.map(&normalize_map/1)
      |> Enum.reject(&row_blank?(&1, ["key", "value"]))
      |> Map.new(fn row ->
        {Map.fetch!(row, "key"), Map.fetch!(row, "value")}
      end)

    put_change(changeset, :static_headers, if(headers == %{}, do: nil, else: headers))
  end

  defp cast_fixed_value(%{"source" => "llm"}), do: nil

  defp cast_fixed_value(%{"type" => type, "value" => value}) do
    case {type, value} do
      {_type, value} when value in [nil, ""] -> nil
      {"string", value} -> to_string(value)
      {"integer", value} -> parse_integer(value)
      {"number", value} -> parse_float(value)
      {"boolean", value} -> parse_boolean(value)
      {_other, value} -> value
    end
  end

  defp normalize_param_rows(rows) do
    rows
    |> normalize_rows()
    |> Enum.map(fn row ->
      %{
        "name" => trim_text(Map.get(row, "name", "")),
        "type" => trim_text(Map.get(row, "type", "string")),
        "source" => trim_text(Map.get(row, "source", "llm")),
        "value" => trim_text(Map.get(row, "value", ""))
      }
    end)
  end

  defp normalize_header_rows(rows) do
    rows
    |> normalize_rows()
    |> Enum.map(fn row ->
      %{
        "key" => trim_text(Map.get(row, "key", "")),
        "value" => trim_text(Map.get(row, "value", ""))
      }
    end)
  end

  defp normalize_rows(rows) when is_list(rows), do: Enum.map(rows, &normalize_map/1)

  defp normalize_rows(rows) when is_map(rows) do
    rows
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {_key, value} -> normalize_map(value) end)
  end

  defp normalize_rows(_rows), do: []

  defp normalize_http_method(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_http_method(value), do: value

  defp normalize_map(value) when is_map(value),
    do: Enum.into(value, %{}, fn {k, v} -> {to_string(k), v} end)

  defp normalize_map(_value), do: %{}

  defp row_blank?(row, keys) do
    Enum.all?(keys, fn key -> blank?(Map.get(row, key)) end)
  end

  defp valid_identifier?(value), do: String.match?(value, ~r/^[A-Za-z_][A-Za-z0-9_]*$/)

  defp stringify_value(nil), do: ""
  defp stringify_value(value) when is_binary(value), do: value
  defp stringify_value(value), do: to_string(value)

  defp parse_boolean(value) when value in [true, "true", "1", 1], do: true
  defp parse_boolean(value) when value in [false, "false", "0", 0], do: false
  defp parse_boolean(value), do: value

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> parsed
      _ -> value
    end
  end

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1

  defp parse_float(value) do
    case Float.parse(to_string(value)) do
      {parsed, ""} -> parsed
      _ -> value
    end
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value

  defp blank?(value), do: value in [nil, ""]
end
