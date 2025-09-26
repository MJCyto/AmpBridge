defmodule AmpBridgeWeb.Layouts do
  use AmpBridgeWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the root layout.
  """
  def root(assigns) do

    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable] bg-neutral-900">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title suffix=" · AmpBridge">
          <%= assigns[:page_title] || "Home" %>
        </.live_title>
        <link phx-track-static rel="stylesheet" href="/css/app.css" />
        <link rel="icon" type="image/svg+xml" href="/Ampbridge.svg" id="favicon" />
        <script defer phx-track-static type="text/javascript" src="/js/app.js"></script>
        <script>
          function updateFavicon() {
            const favicon = document.getElementById('favicon');
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
              favicon.href = '/Ampbridge-dark.svg';
            } else {
              favicon.href = '/Ampbridge-light.svg';
            }
          }

          updateFavicon();

          if (window.matchMedia) {
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateFavicon);
          }
        </script>
      </head>
      <body
        class="bg-neutral-900 text-neutral-100 antialiased min-h-screen"
        x-bind:class="{ 'nav-expanded': navExpanded }"
        x-data="{ navExpanded: localStorage.getItem('nav-expanded') == 'true' }"
        x-init="$watch('navExpanded', value => localStorage.setItem('nav-expanded', value))"
      >
        <div class="w-screen h-screen">
          <%= @inner_content %>
        </div>
      </body>
    </html>
    """
  end
end
