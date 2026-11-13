# Contributing

Contributions are welcome. This repository is public. Bug reports, fixes,
and documentation improvements are all useful.

## Issues

Open a GitHub issue for a bug, a question about behavior, or a change you
want to discuss before writing it. Search open issues first.

Include the addon version, the Godot version, and the steps that show the
problem. Do not paste access tokens, passwords, or private endpoints.

## Pull requests

1. Fork the repository and branch from `sdk-dev`.
2. Keep the change focused.
3. Use a [Conventional Commits](https://www.conventionalcommits.org/)
   subject:

   `type(scope): subject`

   `type` is one of `feat`, `fix`, `docs`, `deps`, `style`, `refactor`,
   `perf`, `test`, `build`, `ci`, `chore`, or `revert`. `scope` is
   optional.
4. Open the pull request against `sdk-dev`, where work lands before it is
   promoted to `main` (see Releases in the README). Say what changed and how
   you checked it.

Do not commit access tokens, passwords, private endpoints, or local
credentials.

## Checks

Godot 4.5.1 is the version this repository is written for. From the
repository root, these scripts keep their fixtures in this tree:

```sh
godot --headless --path . --script protocol_test.gd
godot --headless --path . --script session_test.gd
godot --headless --path . --script handoff_test.gd
```

Each one prints `HAIVEN_TEST_PASS` and exits 0 on success.

`Haiven.Godot.csproj` references the public `haiven-sdk-unity` core.
That checkout is not required for the three scripts above.
