# RunPulse

Menu bar app that follows the GitHub Actions runs **you** trigger — pushes, tags, manual dispatches — across all your repos. Shows how many are running, notifies when each finishes (naming the failing job › step), and goes quiet again.

## Installation

### Homebrew

```bash
brew tap PhilRoli/tap
brew install --cask runpulse
```

RunPulse is ad-hoc signed (not notarized). On first launch, right-click the app in Finder and choose "Open" to bypass Gatekeeper, or run:

```bash
xattr -dr com.apple.quarantine /Applications/RunPulse.app
```

## Sign-in

RunPulse uses the GitHub CLI's login: install [`gh`](https://cli.github.com) and run `gh auth login` (scopes `repo`, `read:org`). Without `gh`, paste a personal access token in Preferences — it's stored in the login Keychain via `/usr/bin/security`.

## How it works

- Repos: every repo you can push to that was pushed in the last 7 days (1/3/7/14 in Preferences); uncheck repos to mute them.
- Runs: `GET /repos/{repo}/actions/runs?actor=<you>`, every 10 s while something is running, otherwise every 60 s, with ETags so unchanged polls don't count against the rate limit. Pull-request and scheduled runs are ignored.
- Menu bar: icon only when idle, the number of running runs, a green ✓ for 5 minutes after a pass, a red ✗ after a failure until you open the menu, an orange `!` when signed out.

## Development

- Build + install locally: `./rebuild.sh` (installs to /Applications, ad-hoc signed).
- Tests: `swift test`. Lint: `swiftlint --strict`.
- Release: push a tag `vX.Y.Z`. The Release workflow builds a universal app, publishes `RunPulse-X.Y.Z.app.zip` and updates `Casks/runpulse.rb` in `PhilRoli/homebrew-tap` (needs the `HOMEBREW_TAP_TOKEN` repo secret).
- Regenerate the icon: `scripts/make-icon.sh`.

## License

MIT
