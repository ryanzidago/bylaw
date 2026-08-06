defmodule Bylaw.HTML.Check.RequireImageAltPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.RequireImageAlt

  property "every image with an alt attribute passes validation" do
    check all(
            alt <-
              one_of([
                string(:alphanumeric, max_length: 80),
                member_of(["", "Résumé portrait", "Διακοσμητική εικόνα", "商品写真"])
              ]),
            source <- string(:alphanumeric, min_length: 1, max_length: 80),
            markup <- member_of([:double_quoted, :single_quoted, :reordered, :self_closing]),
            wrapper <- member_of([:bare, :div, :figure])
          ) do
      image = image_markup(markup, source, alt)
      html = wrap_image(wrapper, image)

      assert HTML.validate_html(html, [RequireImageAlt]) == :ok
    end
  end

  defp image_markup(:double_quoted, source, alt),
    do: ~s(<img class="generated" src="/#{source}" alt="#{alt}">)

  defp image_markup(:single_quoted, source, alt),
    do: "<img src='/#{source}' alt='#{alt}' loading='lazy'>"

  defp image_markup(:reordered, source, alt),
    do: ~s(<img alt="#{alt}" data-source="generated" src="/#{source}">)

  defp image_markup(:self_closing, source, alt),
    do: ~s(<img\n  src="/#{source}"\n  alt="#{alt}"\n/>)

  defp wrap_image(:bare, image), do: image
  defp wrap_image(:div, image), do: "<div><span>Before</span>#{image}<span>After</span></div>"
  defp wrap_image(:figure, image), do: "<figure>#{image}<figcaption>Caption</figcaption></figure>"
end
