defmodule Mix.Tasks.InstallHooks do
  @shortdoc "Installs git pre-commit hook to enforce formatting"
  @moduledoc """
  Copies the pre-commit hook to .git/hooks so commits are blocked when code
  is not formatted. Run once after cloning, or as part of `mix setup`.
  """

  use Mix.Task

  def run(_args) do
    repo_root = Path.dirname(File.cwd!())
    hooks_dir = Path.join([repo_root, ".git", "hooks"])
    hook_src = Path.join(["priv", "git_hooks", "pre-commit"])
    hook_dst = Path.join(hooks_dir, "pre-commit")

    unless File.exists?(Path.join(repo_root, ".git")) do
      Mix.shell().error("Not a git repository (no .git found). Skipping hook install.")
      exit(:normal)
    end

    File.mkdir_p!(hooks_dir)
    File.cp!(hook_src, hook_dst)
    File.chmod!(hook_dst, 0o755)

    Mix.shell().info(
      "✓ Pre-commit hook installed. Commits will be blocked if code is not formatted."
    )
  end
end
