{
  description = "Floxpkgs/Project Template";
  # Allow the floxEnv prompt to persist.
  # nixConfig.bash-prompt = "[flox] \\[\\033[38;5;172m\\]λ \\[\\033[0m\\]";

  # This is needed due to a bug in how Nix handles triple inputs + follows and
  # we are using this from flox repository
  inputs.flox.url = "github:flox/flox";
  inputs.flox.inputs.flox-floxpkgs.follows = "flox-floxpkgs";
  inputs.flox.inputs.flox-bash.follows = "/";

  inputs.flox-floxpkgs.url = "github:flox/floxpkgs";
  inputs.flox-floxpkgs.inputs.flox-bash.follows = "/";
  inputs.flox-floxpkgs.inputs.flox.follows = "flox";

  # Declaration of external resources
  # =================================
  # =================================

  outputs = args @ {flox-floxpkgs, ...}: flox-floxpkgs.project args (_: {});
}
