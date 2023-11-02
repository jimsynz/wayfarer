import Config

config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://code.harton.nz/james/wayfarer",
  manage_mix_version?: true,
  version_tag_prefix: "v",
  manage_readme_version: "README.md"

config :wayfarer,
  start_listener_supervisor?: config_env() != :test,
  start_target_supervisor?: config_env() != :test
