# OmaXerahs agent instructions

OmaXerahs is an Omarchy shell plugin (QML + JavaScript) that uploads Omarchy screenshots through the XerahS `omaxerahs` CLI. The CLI lives in `KovaForge/XerahS`; this repository is only the plugin.

- Tests: `bash tests/model-test.sh` and `bash tests/run-bounded-test.sh`. Validate the manifest with `omarchy plugin validate "$PWD"`.
- Spawn every helper process through `run-bounded`; do not add unbounded process output collectors.
- Record user-visible changes in `CHANGELOG.md` and keep `manifest.json` `version` in step with it.
- Publishing to the Omarchy marketplace: [.ai/skills/publish-marketplace/SKILL.md](.ai/skills/publish-marketplace/SKILL.md).
