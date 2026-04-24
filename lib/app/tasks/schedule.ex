defmodule App.Tasks.Schedule do
  @moduledoc false

  @every_units [:minute, :hour, :day, :week, :month]
  @schedule_types [:once, :every, :cron]

  def schedule_types, do: @schedule_types
  def every_units, do: @every_units

  def parse_datetime_input(nil), do: {:error, :blank}
  def parse_datetime_input(""), do: {:error, :blank}

  def parse_datetime_input(value) when is_binary(value) do
    normalized =
      case String.length(value) do
        16 -> value <> ":00"
        _other -> value
      end

    with {:ok, naive} <- NaiveDateTime.from_iso8601(normalized),
         {:ok, datetime} <- DateTime.from_naive(naive, "Etc/UTC") do
      {:ok, ensure_usec(datetime)}
    else
      _other -> {:error, :invalid}
    end
  end

  def format_datetime_input(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_naive()
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  def format_datetime_input(_other), do: nil

  def next_run_after(%{repeat: false}, _from_datetime), do: nil

  def next_run_after(
        %{repeat: true, schedule_type: :cron, cron_expression: expression},
        from_datetime
      )
      when is_binary(expression) do
    with {:ok, cron_expression} <- Crontab.CronExpression.Parser.parse(expression),
         {:ok, next_naive} <-
           Crontab.Scheduler.get_next_run_date(cron_expression, DateTime.to_naive(from_datetime)),
         {:ok, next_datetime} <- DateTime.from_naive(next_naive, "Etc/UTC") do
      {:ok, ensure_usec(next_datetime)}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_cron_expression}
    end
  end

  def next_run_after(
        %{repeat: true, schedule_type: :every, every_interval: interval, every_unit: unit},
        %DateTime{} = from_datetime
      )
      when is_integer(interval) and interval > 0 and unit in @every_units do
    {:ok, shift_every(from_datetime, interval, unit)}
  end

  def next_run_after(_task, _from_datetime), do: {:error, :invalid_schedule}

  def valid_cron_expression?(expression) when is_binary(expression) do
    case Crontab.CronExpression.Parser.parse(expression) do
      {:ok, _parsed} -> :ok
      {:error, _reason} -> {:error, :invalid_cron_expression}
    end
  end

  def valid_cron_expression?(_expression), do: {:error, :invalid_cron_expression}

  defp shift_every(datetime, interval, :minute),
    do: DateTime.add(datetime, interval * 60, :second)

  defp shift_every(datetime, interval, :hour),
    do: DateTime.add(datetime, interval * 3_600, :second)

  defp shift_every(datetime, interval, :day),
    do: DateTime.add(datetime, interval * 86_400, :second)

  defp shift_every(datetime, interval, :week),
    do: DateTime.add(datetime, interval * 604_800, :second)

  defp shift_every(datetime, interval, :month) do
    naive = DateTime.to_naive(datetime)
    date = NaiveDateTime.to_date(naive)
    time = NaiveDateTime.to_time(naive)
    shifted_date = shift_date_by_months(date, interval)
    {:ok, shifted_naive} = NaiveDateTime.new(shifted_date, time)

    shifted_naive
    |> DateTime.from_naive!("Etc/UTC")
    |> ensure_usec()
  end

  defp shift_date_by_months(%Date{} = date, months) when is_integer(months) do
    month_index = date.year * 12 + date.month - 1 + months
    year = div(month_index, 12)
    month = rem(month_index, 12) + 1
    day = min(date.day, Date.days_in_month(%Date{year: year, month: month, day: 1}))
    %Date{year: year, month: month, day: day}
  end

  defp ensure_usec(%DateTime{} = datetime), do: %{datetime | microsecond: {0, 6}}
end
