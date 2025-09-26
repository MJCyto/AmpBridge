defmodule Mix.Tasks.Dev do
  use Mix.Task

  @shortdoc "Starts Phoenix server with live asset reloading"

  def run(_args) do
    # Build assets first
    Mix.Task.run("assets.build")
    
    # Start webpack in watch mode in the background
    webpack_pid = start_webpack_watch()
    
    # Start Phoenix server
    Mix.Task.run("phx.server")
    
    # Clean up webpack when server stops
    cleanup_webpack(webpack_pid)
  end

  defp start_webpack_watch do
    spawn(fn ->
      System.cmd("npm", ["run", "watch"], cd: "assets", into: IO.stream())
    end)
  end

  defp cleanup_webpack(pid) do
    Process.exit(pid, :kill)
  end
end
