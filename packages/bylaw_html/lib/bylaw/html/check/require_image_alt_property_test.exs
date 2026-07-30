defmodule Bylaw.HTML.Check.RequireImageAltPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.RequireImageAlt

  property "every image with an alt attribute passes validation" do
    check all(
            alt <- string(:alphanumeric, max_length: 80),
            source <- string(:alphanumeric, min_length: 1, max_length: 80)
          ) do
      html = ~s(<img src="/#{source}" alt="#{alt}">)

      assert HTML.validate_html(html, [RequireImageAlt]) == :ok
    end
  end
end
