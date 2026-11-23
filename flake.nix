{
  description = "Kandev autonomous agent platform";

  inputs = {
    flake-lib = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:jgus-org/flake-lib/v1";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      flake-lib,
      nixpkgs,
      ...
    }:
    let
      pin = import ./pin.nix;
      source = {
        owner = "kdlbs";
        repo = "kandev";
        type = "github";
      };
    in
    flake-lib.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        orgFormatting = flake-lib.lib.mkFormatting {
          inherit self system;
        };
        src = pkgs.fetchFromGitHub {
          hash = pin.sourceHash;
          owner = source.owner;
          repo = source.repo;
          rev = pin.sourceRev;
        };
      in
      {
        checks.formatting = orgFormatting.check;
        formatter = orgFormatting.formatter;
        packages = {
          kandev-source = src;
          plugin-pack = pkgs.buildGoModule {
            inherit src;
            env.CGO_ENABLED = "0";
            ldflags = [
              "-s"
              "-w"
            ];
            meta.mainProgram = "plugin-pack";
            modRoot = "apps/backend";
            pname = "kandev-plugin-pack";
            subPackages = [ "cmd/plugin-pack" ];
            vendorHash = pin.vendorHash;
            version = pin.version;
          };
        }
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") (
          let
            kandevPatches = [
              ./patches/managed-configuration.patch
              ./patches/agent-instruction-inheritance.patch
              ./patches/instruction-only-profile-delivery.patch
              ./patches/normal-task-instruction-prompt.patch
              ./patches/credential-transcript-redaction.patch
              ./patches/linked-worktree-additional-directories.patch
              ./patches/task-create-initial-model.patch
              ./patches/qwen-executable-override.patch
              ./patches/advisory-initial-stall.patch
              ./patches/terminal-session-ended-gone.patch
              ./patches/ask-user-question-wait-deadline.patch
              ./patches/kandev-agent.patch
            ];
          in
          rec {
            default = kandev;
            kandev = pkgs.buildGoModule {
              inherit src;
              # Each entry guards behavior a local patch adds or rewrites; upstream's own suite is not run.
              checkPhase = ''
                runHook preCheck
                go test -tags fts5 ./internal/agent/agents -run '^TestQwenACPExecutableOverride$'
                go test -tags fts5 ./internal/common/config -run '^TestManagedConfigFromFile$'
                go test -tags fts5 ./internal/backendapp -run '^TestReconcileManagedInstructions$'
                go test -tags fts5 ./internal/office/skills -run '^TestInstructionListerAdapter'
                go test -tags fts5 ./internal/office/service -run '^TestSkillManifestUsesEffectiveInstructions$'
                go test -tags fts5 ./internal/agent/runtime/lifecycle -run '^TestRunSkillDeploy_(EmptySkillsInvokesDeployer|FreshSessionPrependsEntryInstruction|ResumeDoesNotRepeatEntryInstruction|EmptyEntryOverrideLeavesPromptUnchanged|OfficePromptDoesNotDuplicateEntryInstruction)$'
                go test -tags fts5 ./internal/agent/runtime/lifecycle/skill -run '^(TestDeploy_KanbanProfile_NoSkillsNoOp|TestDeploy_Local_WritesSkillsAndInstructions|TestDeploy_Sprites_RewritesSiblingRefsInManifest)$'
                go test -tags fts5 ./internal/common/appctx -run '^TestDetachedRetainsValuesWithoutParentCancellation$'
                go test -tags fts5 ./internal/agent/runtime/lifecycle -run '^TestRedactAgentEvent'
                go test -tags fts5 ./internal/agentctl/tracing -run '^TestTraceAgentEvent$'
                go test -tags fts5 ./internal/agent/runtime/agentctl -run '^TestNewSessionWithAdditionalDirectories$'
                go test -tags fts5 ./internal/agent/runtime/lifecycle -run '^TestWorkspaceGitAdditionalDirectoriesUsesLinkedWorktreeCommonDir$'
                go test -tags fts5 ./internal/agentctl/server/adapter/transport/acp -run '^TestSessionAdditionalDirectoriesReachACP$'
                go test -tags fts5 ./internal/gateway/websocket -run '^TestHandleTerminalWSEnvironment'
                go test -tags fts5 ./internal/task/handlers -run '^TestWithInitialSessionRuntime'
                go test -tags fts5 ./internal/task/handlers ./internal/orchestrator/messagequeue -run '^TestKandev'
                go test -tags fts5 ./internal/orchestrator/handlers -run '^TestQueuedBrowserSubmission'
                go test -tags fts5 ./internal/agentctl/server/adapter/transport/acp -run '^TestKandev'
                go test -tags fts5 ./internal/agent/runtime/lifecycle -run '^TestKandev'
                go test -tags fts5 ./internal/orchestrator -run '^(TestKandev|TestSendQueuedNow|TestRetryTransientPrompt_)'
                go test -tags fts5 ./internal/task/service -run '^(TestKandev|TestCreateMessageIdempotentReplaysExistingRow)'
                go test -tags fts5 ./internal/backendapp -run '^TestKandev'
                go test -tags fts5 ./internal/orchestrator -run '^(TestHandleAgentStalled|TestStallNoticeContent)'
                go test -tags fts5 ./internal/mcp/server -run '^TestAskUserQuestion_ExpiresInsideTheClientDeadline$'
                runHook postCheck
              '';
              ldflags = [
                "-s"
                "-w"
                "-X main.Version=${pin.version}"
                "-X main.Commit=${pin.sourceRev}"
              ];
              meta = {
                description = "Autonomous agent platform";
                homepage = "https://github.com/kdlbs/kandev";
                license = pkgs.lib.licenses.agpl3Only;
                mainProgram = "kandev";
                platforms = [ "x86_64-linux" ];
              };
              modRoot = "apps/backend";
              nativeCheckInputs = [ pkgs.git ];
              patches = kandevPatches;
              pname = "kandev";
              postBuild = ''
                for TARGET in linux/amd64 linux/arm64 darwin/arm64 darwin/amd64; do
                  TARGET_GOOS="''${TARGET%/*}"
                  TARGET_GOARCH="''${TARGET#*/}"
                  CGO_ENABLED=0 GOOS="''${TARGET_GOOS}" GOARCH="''${TARGET_GOARCH}" go build \
                    -ldflags "''${ldflags[*]}" \
                    -o "''${GOPATH}/bin/agentctl-''${TARGET_GOOS}-''${TARGET_GOARCH}" \
                    ./cmd/agentctl
                done
              '';
              preBuild = ''
                rm -rf internal/webapp/embedded/generated
                mkdir -p internal/webapp/embedded/generated
                cp -R ${kandev-web}/. internal/webapp/embedded/generated/
              '';
              subPackages = [
                "cmd/kandev"
                "cmd/agentctl"
              ];
              tags = [ "fts5" ];
              vendorHash = pin.vendorHash;
              version = pin.version;
            };
            kandev-mock-agent = pkgs.buildGoModule {
              inherit src;
              doCheck = false;
              meta = {
                inherit (kandev.meta) homepage license platforms;
                description = "Kandev test ACP agent";
                mainProgram = "mock-agent";
              };
              modRoot = "apps/backend";
              patches = kandevPatches;
              pname = "kandev-mock-agent";
              subPackages = [ "cmd/mock-agent" ];
              tags = [ "fts5" ];
              vendorHash = pin.vendorHash;
              version = pin.version;
            };
            kandev-web =
              let
                webDeps = flake-lib.lib.mkPnpmDeps {
                  inherit pkgs src;
                  fetcherVersion = 4;
                  hash = pin.pnpmDepsHash;
                  pname = "kandev-web";
                  pnpmMajor = pin.pnpmMajor;
                  sourceFingerprint = pin.sourceHash;
                  sourceRoot = "${src.name}/apps";
                  version = pin.version;
                  workspaceDir = "apps";
                };
                webToolchain = webDeps.passthru.pnpmToolchain;
              in
              pkgs.stdenvNoCC.mkDerivation {
                buildPhase = ''
                  runHook preBuild
                  KANDEV_VERSION=${pin.version} VITE_KANDEV_API_PORT= VITE_KANDEV_DEBUG= pnpm --filter @kandev/web build
                  runHook postBuild
                '';
                checkPhase = ''
                  runHook preCheck
                  pnpm --filter @kandev/web exec vitest run \
                    app/office/components/new-task-dialog.test.tsx \
                    components/task-create-dialog-helpers.test.ts \
                    components/task-create-dialog-submit.test.tsx \
                    components/task-create-model-selector.test.ts \
                    components/task/chat/route-panel-mouse-down.test.tsx \
                    components/task/use-passthrough-terminal.test.ts \
                    components/task/use-subtask-submit.test.ts \
                    hooks/domains/session/use-queue-provenance.test.tsx \
                    hooks/domains/session/use-session-message-fetch.test.ts \
                    hooks/use-message-handler.test.ts
                  runHook postCheck
                '';
                doCheck = true;
                installPhase = ''
                  runHook preInstall
                  mkdir -p "${placeholder "out"}"
                  cp -R web/dist/. "${placeholder "out"}/"
                  runHook postInstall
                '';
                nativeBuildInputs = [
                  pkgs.nodejs
                  pkgs.pnpmConfigHook
                  webToolchain.pnpm
                ];
                patches = [
                  ./patches/session-model-picker-focus.patch
                  ./patches/task-create-model-picker.patch
                  ./patches/terminal-ended-reconnect-stop.patch
                  ./patches/transcript-fetch-failure-recovery.patch
                  ./patches/kandev-agent-web.patch
                ];
                pname = "kandev-web";
                pnpmDeps = webDeps;
                sourceRoot = "${webToolchain.src.name}/apps";
                src = webToolchain.src;
                version = pin.version;
              };
            update-branches = flake-lib.lib.mkUpdateBranches {
              inherit pkgs source;
              extraHashes = [
                "pnpmMajor"
                "vendorHash"
              ];
              minimumTrackingVersion = "0.92.0";
              pinSchema = "github-pnpm";
            };
            update-version = flake-lib.lib.mkUpdateVersion {
              inherit pkgs source;
              artifactHook = flake-lib.lib.mkPnpmDeclarationHook {
                inherit pkgs;
                manifestPath = "apps/package.json";
              };
              buildFailureHashes = [
                "pnpmDepsHash"
                "vendorHash"
              ];
              extraHashes = [ "pnpmMajor" ];
            };
          }
        );
      }
    );
}
