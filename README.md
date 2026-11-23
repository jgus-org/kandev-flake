# kandev

A Nix flake that provides [Kandev](https://github.com/kdlbs/kandev), a platform that runs autonomous coding agents against a task board.

## Outputs

| Attribute                                | Systems                     | What you get                                                                                                                                                                                                         |
| ---------------------------------------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages.kandev` (= `packages.default`) | `x86_64-linux`              | `bin/kandev`, the server, with its web frontend embedded, plus `bin/agentctl` and the `agentctl-<os>-<arch>` cross-builds of that same program for `linux/amd64`, `linux/arm64`, `darwin/amd64`, and `darwin/arm64`. |
| `packages.kandev-web`                    | `x86_64-linux`              | The built frontend on its own, as static files.                                                                                                                                                                      |
| `packages.kandev-mock-agent`             | `x86_64-linux`              | `bin/mock-agent`, Kandev's test ACP agent.                                                                                                                                                                           |
| `packages.kandev-source`                 | all three published systems | The pinned upstream source tree, for compiling against Kandev's backend and plugin SDK.                                                                                                                              |
| `packages.plugin-pack`                   | all three published systems | `bin/plugin-pack`, Kandev's plugin archive packager.                                                                                                                                                                 |

The flake publishes attributes for `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. The server, its frontend, and the mock agent are published for `x86_64-linux` only (the server and the mock agent additionally declare `x86_64-linux` as their only supported platform), so the other two systems carry just the source and packager attributes.

```sh
nix build .#kandev
```

## Notes

- The frontend needs no separate deployment: it is embedded in the server binary.
- Building this flake installs, enables, and deploys nothing. Where Kandev runs, which state it writes, and which coding-agent CLIs it is configured to launch all belong to the consumer.

## Kandev Agent

The optional built-in `kandev-agent` registry entry launches a consumer-provided `kandev-agent` executable over ACP stdio with no arguments, resolved by name on the server's `PATH`. Its session directory defaults to `{home}/.local/state/kandev-agent`. The entry declares a native-turn protocol version, and a version the backend does not support blocks launch.

Provenance comes from trusted ingress, not from prompt text. The dedicated browser composer (`message.submit`) and task submission (`POST /api/v1/tasks/submit`) attest `HUMAN`, and only for verified nonsynthetic cookie sessions; task submission carries the exact original prompt separately from the description derived from it. Generic message and task creation, automation, personal access tokens, unauthenticated or synthetic sessions, and unidentified legacy launch paths remain `CLIENT`. Verified browser controls attest `HUMAN` and other controls default to `CLIENT`. Other agents keep upstream's streaming insertion behavior.

See [LICENSE.md](LICENSE.md) for licensing and copyright, and [NOTICE.md](NOTICE.md) for the terms of upstream and distributed artifacts.
