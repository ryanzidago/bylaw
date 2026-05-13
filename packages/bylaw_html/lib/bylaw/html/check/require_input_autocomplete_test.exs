defmodule Bylaw.HTML.Check.RequireInputAutocompleteTest do
  use ExUnit.Case, async: true

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.RequireInputAutocomplete
  alias Bylaw.HTML.Issue

  describe "validate_html/2 with RequireInputAutocomplete" do
    test "passes text inputs with autocomplete" do
      html = """
      <input name="email" autocomplete="email">
      <input type="password" name="password" autocomplete="current-password">
      <input type="search" name="query" autocomplete="off">
      """

      assert :ok = HTML.validate_html(html, [RequireInputAutocomplete])
    end

    test "passes ignored input control types without autocomplete" do
      html = """
      <input type="hidden" name="token" value="abc">
      <input type="checkbox" name="remember">
      <input type="radio" name="plan" value="pro">
      <input type="file" name="avatar">
      <input type="submit" value="Save">
      <input type="button" value="Cancel">
      <input type="reset" value="Reset">
      <input type="image" src="/submit.svg" alt="Submit">
      """

      assert :ok = HTML.validate_html(html, [RequireInputAutocomplete])
    end

    test "ignores input control types case-insensitively" do
      html = """
      <input type="HIDDEN" name="token" value="abc">
      <input type="Checkbox" name="remember">
      """

      assert :ok = HTML.validate_html(html, [RequireInputAutocomplete])
    end

    test "returns an issue for an input without autocomplete" do
      html = ~s(<input type="email" name="email">)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [RequireInputAutocomplete])

      assert issue.check == RequireInputAutocomplete
      assert issue.message == "expected <input> to define a non-blank autocomplete attribute"
      assert issue.tag == "input"
      assert issue.snippet =~ "<input"
      assert issue.snippet =~ ~s(type="email")
    end

    test "returns an issue for an input with blank autocomplete" do
      html = ~s(<input name="search" autocomplete=" ">)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [RequireInputAutocomplete])

      assert issue.check == RequireInputAutocomplete
      assert issue.snippet =~ ~s(autocomplete=" ")
    end

    test "returns every missing autocomplete issue in document order" do
      html = """
      <input name="email">
      <input type="hidden" name="token" value="abc">
      <input name="name" autocomplete="name">
      <input type="password" name="password">
      """

      assert {:error, issues} = HTML.validate_html(html, [RequireInputAutocomplete])

      assert [
               %Issue{check: RequireInputAutocomplete, tag: "input", snippet: first_snippet},
               %Issue{check: RequireInputAutocomplete, tag: "input", snippet: second_snippet}
             ] = issues

      assert first_snippet =~ ~s(name="email")
      assert second_snippet =~ ~s(type="password")
    end
  end
end
