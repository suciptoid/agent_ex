defmodule App.Tasks.ScheduleTest do
  use ExUnit.Case, async: true

  alias App.Tasks.Schedule

  test "cron next_run_after is strictly in the future at boundary times" do
    task = %{repeat: true, schedule_type: :cron, cron_expression: "35 4 * * *"}

    assert {:ok, next_run} = Schedule.next_run_after(task, ~U[2026-04-24 04:35:00Z])
    assert next_run == ~U[2026-04-25 04:35:00.000000Z]
  end
end
