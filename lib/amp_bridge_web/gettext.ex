defmodule AmpBridgeWeb.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext),
  your module gains a set of macros for internationalization
  and pluralization capabilities.
  """
  use Gettext.Backend, otp_app: :amp_bridge
end
