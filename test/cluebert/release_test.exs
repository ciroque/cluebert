defmodule Cluebert.ReleaseTest do
  # Seeds write to the shared "General" collection; keep other tests out of it.
  use Cluebert.DataCase, async: false

  import ExUnit.CaptureIO

  alias Cluebert.{Boards, Release}

  test "seed/0 imports the boards in priv/boards" do
    output = capture_io(fn -> assert :ok = Release.seed() end)

    assert output =~ ~s(Seeded "Sampler" in "General")
    assert Enum.any?(Boards.list_boards(), &(&1.name == "Sampler"))
  end
end
