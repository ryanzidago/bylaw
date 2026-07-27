defmodule Bylaw.Credo.HeexTest do
  use ExUnit.Case, async: true

  alias Bylaw.Credo.Heex

  test "uses the tokenizer provided by the installed Phoenix LiveView version" do
    assert Heex.available?()

    assert [
             %Heex.Tag{type: :tag, name: "button"},
             %Heex.Text{content: "Save"},
             %Heex.CloseTag{name: "button"}
           ] = Heex.tokens("<button type=\"submit\">Save</button>")
  end
end
