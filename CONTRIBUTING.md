# Contributing to AutoClip

Contributions to the Windows installer, updater, maintenance helpers, tests, and documentation are welcome. Application source is available from the [v1.0.0 release](https://github.com/Farkoal2128/AutoClip-MVP/releases/download/v1.0.0/autoclip-1.0.0.tar.gz); this repository remains focused on distribution files.

## Before making a change

Check existing [issues](https://github.com/Farkoal2128/AutoClip-MVP/issues), and describe the problem and expected behavior. Discuss larger changes with the maintainer before implementing them. For security vulnerabilities, follow [SECURITY.md](SECURITY.md).

Use a branch for your change. Keep the scope small, preserve unrelated work, and retain applicable copyright and third-party notices. Contributions to AutoClip-authored files are submitted under the repository's [MIT license](LICENSE); third-party materials retain their own terms.

## Verification and pull requests

Use [BUILDING.md](BUILDING.md) for Windows prerequisites and build commands. For installer or updater behavior changes, document the requirement, add the smallest meaningful failing test, implement the change, and verify that the test passes. Run the applicable distribution checks:

```powershell
python -m unittest discover -s tests -v
```

Include the problem, resulting behavior, exact verification commands and results, and any untested paths in your pull request. Installer lifecycle changes need local installation, update, rollback, uninstall, and preservation checks on the exact candidate. State whether acquisition was cached and which CPU or NVIDIA paths were exercised. Documentation-only changes need link, command, and consistency review; application or installer execution is not required for those changes.

Do not commit generated installers, runtime ZIPs, wheels, credentials, or personal media. Do not alter published release assets or weaken hash, consent, health, rollback, or ownership checks to make a build pass. The maintainer approves and publishes releases.

## Contributors

| Contributor | Role |
| --- | --- |
| Jad Ghazi ([Farkoal2128](https://github.com/Farkoal2128)) | Creator, maintainer, and release owner |
| [Codex (@codex)](https://github.com/codex) | OpenAI AI development assistant contributing implementation, testing, packaging, and documentation assistance under the maintainer's direction |

These credits acknowledge contributions to the project. Codex is credited as an AI assistant; maintainer responsibilities and release decisions remain with Jad Ghazi. For work produced with Codex, add this trailer after a blank line in the commit message:

```text
Co-authored-by: Codex <267193182+codex@users.noreply.github.com>
```

The trailer uses the GitHub no-reply identity for [@codex](https://github.com/codex). GitHub's automatic Contributors view is based on commit authorship and is separate from this credit list.
