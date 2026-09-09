# Remote agent box

Scripts to turn a fresh Linux VM into a machine that runs AI coding agents
while your laptop is closed.

## The short version

Agents run on a server. Your laptop is a window onto that server. The window
can close, move, or be replaced without the work noticing.

Two tools do it:

- **herdr** is a terminal multiplexer built for agents. It holds each agent in
  a pane on the server, keeps them alive when you disconnect, and shows a
  sidebar telling you which pane is *working*, which is *blocked* waiting for
  your answer, and which is *done*.
- **Tailscale** gives every machine you own a stable private name. `ssh work`
  reaches your server from your laptop, your phone, or a cafe, with no public
  ports, no port forwarding, and no VPN configuration.

Neither makes agents smarter or faster. They change where agents live and how
you supervise them.

## What you actually get

### Work continues when you do not

Close the laptop, get on a plane, go to sleep. The agents kept running. Come
back and everything is where you left it, output intact. This is the headline
benefit but it is not the only one.

### One view of agent state

Running four agents without herdr means cycling through four terminal tabs
asking "is this one done yet?" and losing your place. herdr shows a list with
a status beside each pane. You glance at it and go directly to the one that
needs you.

This is what makes parallelism tolerable. The bottleneck in multi-agent work
is not compute, it is your attention, and the sidebar is what stops attention
leaking into polling.

### The agents are not on your laptop

An agent with permission to run commands is a process you have given a lot of
trust. On a server, the blast radius is a machine you can rebuild in two
minutes with the bootstrap script. Nothing it does touches your photos, your
SSH keys, or your other work.

You also stop installing the mess. Test databases, language runtimes,
half-finished dependency experiments, all of it lives on the box and dies with
it.

### Agents get a real Linux environment

Agent tooling assumes Unix. Package managers, CLI tools, containers, file
paths, permissions. On Linux everything is a config file or a command line
tool, which is exactly the interface an agent works well with. Fewer "that
does not work on macOS" detours.

### Your laptop stops being a workstation

No fans, no battery drain, no thermal throttling because three agents are
running test suites. The work happens elsewhere. A cheap laptop and an
expensive laptop give you the same experience.

### Any device, same session

Tailscale puts your phone on the same network. An agent gets stuck at 8am
while you are making coffee, you answer the question from your phone, and it
carries on. A terminal app plus `ssh work` is the whole setup.

### Nothing is exposed to the internet

Your server has no public SSH port. It is unreachable except from devices on
your own network. No brute force attempts in the logs, no fail2ban, no
firewall rules to maintain.

### No SSH key management

Tailscale SSH handles authentication. No key files to copy between machines,
no `IdentityFile` lines, no `known_hosts` conflicts when a machine's address
changes. New machine, new name, it just works.

### Machines are disposable

Spin up a box, run one command, and it joins your network under a name you
choose. Tear it down and, with an ephemeral auth key, it removes itself.
Rented compute becomes something you use for an afternoon rather than
something you carefully maintain.

### Machines can reach each other

Your always-on box can reach a GPU server, a machine at home, a NAS. An agent
in a pane can start a job on another machine and watch it, because from its
point of view they are on the same network.

## What this does not give you

More review capacity. Reading four diffs is still four diffs, and no amount
of tooling makes you check them faster. Treat this as removing friction from
work you were already going to do, not as a throughput multiplier.

If you use one agent at a time, on your own laptop, in one window, and you
never walk away mid-task, you do not need any of this.

## What you need before starting

1. A Linux VM you can SSH into. Ubuntu 22.04 or newer. Any provider.
   2 vCPU and 8 GB RAM is enough for two or three agents.
2. A free Tailscale account at https://tailscale.com
3. A Claude subscription or an Anthropic API key.
4. A GitHub account, or anywhere else you can host a file at a public URL.

## Files

| File | Runs on | Purpose |
| --- | --- | --- |
| `bootstrap.sh` | the server | Installs everything. One command, about two minutes. |
| `agentbox.sh` | your laptop | Small helpers. Optional. |

## One-time setup

### 1. Host the bootstrap script

Push `bootstrap.sh` to a public GitHub repo. You need a raw URL that `curl`
can reach from a brand new machine with nothing on it. It looks like:

```
https://raw.githubusercontent.com/giannisp09/herdr-tailscale-setup/main/bootstrap.sh
```

### 2. Create a Tailscale auth key

In the Tailscale admin console, go to **Settings** then **Keys** then
**Generate auth key**.

- Tick **Reusable** so the same key works for every machine.
- Tick **Ephemeral** if your servers are disposable. Ephemeral machines
  remove themselves from your network when they shut down, which stops you
  accumulating dead entries.
- Set an expiry you are comfortable with.

Copy the key. A whole one has three parts,
`tskey-auth-<keyID>-<secret>`, for example
`tskey-auth-k123456CNTRL-abcdefghijklmnopqrstuvwxyz`. **Select it with a
triple-click or select-all, not a double-click.** A double-click stops at the
first dash and hands you `tskey-auth-k123456CNTRL` with the secret missing,
which looks like a key and is rejected as one.

The same **Keys** page also offers API access tokens, which start with
`tskey-api-` and look close enough to grab by mistake. They cannot authenticate
a machine. Either mistake gives you `backend error: invalid key`, which does not
tell you which one you made.

### 3. Put the key in your shell

On your laptop, in `~/.zshrc` or `~/.bashrc`:

```bash
export TSKEY=tskey-auth-xxxxxxxxxxxx
```

Open a new terminal so it takes effect. This is for your laptop only.
SSH does not send `TSKEY` to the server.

### 4. Install Tailscale on your laptop

```bash
brew install tailscale && sudo tailscale up
```

Or download the app from tailscale.com and log in. Use the same account as
the key above.

## Provisioning a server

Do this for each new machine. The last word is the hostname on your
network. Pick something short. `work`, `gpu1`, `build`.

**From the server** (after you SSH in), paste the key itself. `$TSKEY` is
empty here even if it is set on your laptop:

```bash
curl -fsSL https://raw.githubusercontent.com/giannisp09/herdr-tailscale-setup/main/bootstrap.sh \
  | TSKEY='tskey-auth-xxxxxxxxxxxx' bash -s work
```

**From the laptop**, so `$TSKEY` expands before SSH:

```bash
ssh user@host "curl -fsSL https://raw.githubusercontent.com/giannisp09/herdr-tailscale-setup/main/bootstrap.sh | TSKEY='$TSKEY' bash -s work"
```

If you sourced `agentbox.sh`, `bootstrap-cmd work` copies the first form
with the key already filled in. Paste that on the server.

The script installs Tailscale, herdr, git, Node, and Claude Code, then prints
a summary. It is safe to run twice.

### Optional environment variables

| Variable | Effect |
| --- | --- |
| `TSKEY` | **Required.** Your Tailscale auth key. |
| `GIT_NAME` | Sets `git config --global user.name` |
| `GIT_EMAIL` | Sets `git config --global user.email` |
| `CLAUDE_CODE_OAUTH_TOKEN` | A long-lived subscription token. Set this and the box needs no interactive login at all. Make one on your laptop with `claude setup-token`. |
| `ANTHROPIC_API_KEY` | Only if you are paying per token. **Leave this unset if you have a Claude subscription**, otherwise you will be billed twice. |

## First connection

From your laptop:

```bash
ssh root@work
```

Tailscale handles the authentication, so there is no key file to specify and
no password.

Spell out the username. A bare `ssh work` connects as your **laptop's**
username, which usually does not exist on the server — most container hosts
(Vast.ai, RunPod) give you root and nothing else. Use whatever account the box
actually has. The default tailnet policy permits root; if you have edited your
policy file, `root` must be in the `users` list of its `ssh` rule.

The first connection may open a browser to re-authenticate. That is the
default policy's `check` action, not a failure.

If the name does not resolve, enable **MagicDNS** in the Tailscale admin
console under **DNS**, or use the IP address the bootstrap script printed.
SSH works over the raw `100.x` address either way.

### Sign in to Claude Code

Best done once, on your laptop, so no server ever needs a browser:

```bash
claude setup-token
```

That prints a long-lived token. Pass it to every box you provision:

```bash
curl -fsSL <raw-url> | \
  TSKEY='tskey-auth-...' CLAUDE_CODE_OAUTH_TOKEN='...' bash -s work
```

The box comes up already signed in, and this step disappears.

Otherwise, log in on the server itself:

```bash
claude
```

It prints a URL. **Press `c` to copy it** rather than selecting it with the
mouse. The URL is long, it wraps across several lines in an SSH terminal, and a
hand-made selection usually stops at a line break — which silently drops
`code_challenge`, the last parameter. Open it on your laptop, sign in, and
paste the code back. Once per server.

## Daily use

From your laptop:

```bash
herdr --remote root@work
```

Your terminal is now showing the herdr session running on the server.

| Key | Action |
| --- | --- |
| `n` | New workspace |
| `ctrl+b` | Enter navigate mode |
| `v` or `-` | Split the pane |
| `c` | New tab |
| `ctrl+b q` | Detach and leave everything running |
| `ctrl+b ?` | Full keymap |

Run `claude` inside a pane. Detach whenever you like. Close the laptop. Come
back hours later, run `herdr --remote work` again, and the pane is exactly
where you left it.

## Running several agents at once

Two agents editing the same directory will overwrite each other's work. Give
each one its own checkout using git worktrees:

```bash
cd ~/myrepo
git worktree add ../myrepo-a -b agent-a
git worktree add ../myrepo-b -b agent-b
```

Then open one herdr workspace per directory. Each agent works on its own
branch and you merge normally afterwards.

Three agents is a comfortable ceiling for most people. The limit is not the
server, it is how many diffs you can actually read before you start approving
things you have not checked.

## Desktop notifications (macOS)

```bash
brew install vjeantet/tap/alerter
herdr plugin install yankewei/herdr-focus-notify
```

You get an alert when an agent finishes or gets stuck. Clicking it jumps
straight to that pane.

## Troubleshooting

**`TSKEY: set TSKEY to a Tailscale reusable auth key`**

The bootstrap script ran with an empty key. That is what happens if you
SSH in and run `TSKEY=$TSKEY`: the variable lives on your laptop, not on
the server. Paste the key on the command line, or run the `ssh user@host
"..."` form from the laptop so `$TSKEY` expands locally.

**`herdr: command not found` over SSH, but it works when you log in normally**

Ubuntu's `.bashrc` exits early for non-interactive shells, so anything at the
bottom of the file never runs when you use `ssh host 'command'`. The bootstrap
script puts the PATH line at the very top for this reason. If you installed by
hand, do the same:

```bash
sed -i '1i export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc
```

This matters beyond the error message, because `herdr --remote` starts the
remote server through exactly that kind of shell.

**`Permission denied (publickey)`**

Your SSH client offered the wrong key. The bootstrap script enables Tailscale
SSH to avoid this entirely. If you are connecting to a machine without it,
name the key explicitly:

```bash
ssh -i ~/.ssh/yourkey -o IdentitiesOnly=yes user@host
```

**`address already in use` when starting tailscaled**

The package installer already started it as a system service. You do not need
to start it yourself. Check with `systemctl status tailscaled`.

**`backend error: invalid key: API key tskey-... not valid`**

Tailscale is installed and running fine. The control plane rejected your key.
"API key" in that message is misleading; it means the auth key. Work through
these in order:

The value in that message is shorter than your key because it is the **key ID**
— the middle segment of `tskey-auth-<keyID>-<secret>` — not a truncated key and
not your secret. That makes it the thing to search for. The bootstrap prints the
same ID when it starts (`auth key tskey-auth-k123456CNTRL-...`), so you can
confirm the key reached the control plane intact.

1. **Find that ID on the Keys page.** Open
   https://login.tailscale.com/admin/settings/keys and look for it.
   - **Not there** — the key was deleted, or you are looking at a different
     tailnet. Check the account switcher at the top left; keys do not work
     across tailnets.
   - **There** — the row shows expiry, reusable, and whether it has been used.
     One of those is your answer.
2. **Wrong kind of key.** Tailscale prefixes say what a key is:
   `tskey-auth-` is an auth key and `tskey-client-` an OAuth client secret,
   both of which work here. `tskey-api-` is an API access token and will not
   authenticate a machine, no matter how valid it is.
   See [key prefixes](https://tailscale.com/docs/reference/key-prefixes).
3. **Placeholder or half a key.** You copied `tskey-auth-xxxxxxxxxxxx` out of
   this README, or double-clicked the key in the admin console, which selects
   only up to the first dash and gives you the keyID with no secret. The
   bootstrap now refuses both before it installs anything, so if it reached
   `tailscale up` your key was whole.
4. **Already used.** A key that is not marked **Reusable** works exactly once,
   and Tailscale revokes it the instant it succeeds. The Keys page says
   `You don't have any valid auth keys` with the spent one filed under
   `1 recently invalidated auth key`, type **Single-use** — note that it can
   sit there with months of expiry left and still be dead. Nothing you do on
   the box recovers it; generate a new key and tick **Reusable**.
5. **Expired or revoked.** Auth keys last 90 days by default and can be set as
   low as 1. Generate a fresh one.
6. **Stale node identity.** If the machine was registered before and then
   deleted in the admin console, the old node key is still sitting in
   `/var/lib/tailscale/tailscaled.state` and registration fails even with a
   brand new auth key
   ([tailscale#9382](https://github.com/tailscale/tailscale/issues/9382)).
   Clear it with `sudo tailscale logout`, then run the bootstrap again.

**`Invalid OAuth Request` / `Missing code_challenge parameter`**

The OAuth URL you opened was truncated. `code_challenge` is the last parameter
on a URL long enough to wrap over several lines in an SSH terminal, so a
selection that stops at a line break drops exactly that. Press `c` at the login
prompt to copy the whole thing, or avoid the browser flow entirely by passing
`CLAUDE_CODE_OAUTH_TOKEN` to the bootstrap (see **Sign in to Claude Code**).

**`changing settings via 'tailscale up' requires mentioning all non-default flags`**

You already ran `tailscale up` with flags once. Tailscale persists those
preferences even when the login itself failed, so a bare `tailscale up`
afterwards refuses to silently drop them. Re-run with the flags spelled out:

```bash
sudo tailscale up --reset --authkey='tskey-auth-...' --ssh --hostname=work
```

`--reset` returns everything you did not name to its default
([tailscale up reference](https://tailscale.com/kb/1241/tailscale-up)), which
is why the bootstrap script passes it. Without `--reset` the script would not
survive its own second run.

**`failed to connect to local tailscaled`**

The daemon is not running. Installing the package enables the systemd unit but
does not start it when systemd is not PID 1, which is the normal situation in a
container (Docker, Vast.ai, RunPod). Note that `/dev/net/tun` can exist in such
a container while the daemon is still down, so its presence proves nothing. The
bootstrap script probes the daemon, tries systemd, and otherwise starts
`tailscaled --tun=userspace-networking` itself.

That last case is not supervised: if the container restarts, run the bootstrap
script again to bring the daemon back.

**Agent hits a usage limit overnight**

Subscription plans have a rolling session window and a weekly cap, shared
across the Claude app and Claude Code. A long unattended run can consume the
allowance you wanted for your working day. Check where you stand with
`/usage` inside Claude Code before relying on overnight runs, and consider
API billing for genuinely unattended work.

## Cost note

A server that is always on is billed continuously. Hourly cloud pricing that
looks cheap adds up: $0.20 an hour is about $145 a month, where an equivalent
fixed-price VPS is closer to $30.

If your machine needs to be reachable at all times, buy a fixed-price VPS and
run this script on it once. Use hourly cloud instances only for work that
starts and finishes, and shut them down when the job is done.