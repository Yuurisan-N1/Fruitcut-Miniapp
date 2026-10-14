<div align="center">

<img width="100%" alt="header" src="https://capsule-render.vercel.app/api?type=waving&height=210&text=Fruit%20Cut%20Bot&fontAlign=50&fontAlignY=36&fontSize=56&desc=Treasure%20Box%20%7C%20Task%20Ads%20%7C%20Slice%20Arena%20%7C%20Tasks&descAlign=50&descAlignY=58"/>

<img alt="typing" src="https://readme-typing-svg.demolab.com?font=Inter&size=18&duration=3000&pause=650&center=true&vCenter=true&width=900&lines=Telegram+InitData+Sign+In;Treasure+Box+%7C+Reward+Task+Ads;Slice+Arena+%7C+Task+Rewards;Multi-Account+%7C+Sequential+Processing;Proxy+Support+%7C+One+Proxy+Per+Account"/>

<p>
  <img alt="elixir" src="https://img.shields.io/badge/Elixir-1.14%2B-4B275F?logo=elixir&logoColor=white"/>
  <img alt="platform" src="https://img.shields.io/badge/Platform-Fruit%20Cut-111111"/>
  <img alt="multi-account" src="https://img.shields.io/badge/Multi--Account-Supported-111111"/>
  <img alt="proxy" src="https://img.shields.io/badge/Proxy-Supported-111111"/>
  <img alt="author" src="https://img.shields.io/badge/by-Yuurisandesu-111111"/>
</p>

<p>
  <b>Fruit Cut Bot</b> is a full automation bot for the Fruit Cut Telegram Miniapp.<br/>
  It runs the daily cycle on its own: sign in with the account initData, claim the treasure box, claim the reward task ad the server offers, claim the GigaPub, Monetag and Adsgram Daily ad slots, play the slice arena round and claim every task reward the account is eligible for, all across multiple accounts with proxy support and a live countdown between cycles.<br/>
  Built and distributed by <b>Yuurisandesu</b>.
</p>

</div>

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Bot](#running-the-bot)
- [Features](#features)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Requirements

- Elixir `1.14+`
- Erlang/OTP `25+`
- An account on the Fruit Cut miniapp: https://t.me/Fruit_cut_bot

---

## Installation

### Install Elixir

Elixir runs on the Erlang virtual machine, so **Erlang/OTP is required** - Elixir cannot run without
it. Every package manager below installs Erlang/OTP for you as a dependency. The only path that needs
a separate Erlang step is the Windows manual installer (see below).

**Windows:**

*Option A - package manager (recommended, installs Erlang automatically):*

```cmd
winget install Elixir.Elixir
```

*Option B - manual installer (two installers, in this order):*

1. Download and run the **Erlang/OTP installer** from https://www.erlang.org/downloads
2. Run `erl -s halt` to check which OTP version you got
3. Download the **Elixir installer built for that exact OTP** from https://elixir-lang.org/install.html (`elixir-otp-<N>.exe`) and run it

Then open Command Prompt and verify:

```cmd
elixir --version
```

The output prints both versions, for example `Elixir 1.14.0 (compiled with Erlang/OTP 25)`.

**Linux (Ubuntu / Debian):**

```bash
sudo apt-get update
sudo apt-get install -y elixir
elixir --version
```

**macOS:**

```bash
brew install elixir
elixir --version
```

> If you do not have Homebrew, install it first from https://brew.sh

**Termux (Android):**

```bash
pkg update && pkg upgrade -y
pkg install elixir -y
elixir --version
```

> If the `elixir` package is not available in your Termux repository, install an Ubuntu environment first with `pkg install proot-distro`, then `proot-distro install ubuntu`, then `proot-distro login ubuntu` and run the Linux command above inside it.

---

### Clone and Install

**Clone the repository:**

```bash
git clone https://github.com/Yuurisan-N1/Fruitcut-Miniapp.git
cd Fruitcut-Miniapp
```

**Install dependencies:**

This bot uses only the Elixir standard library, so there is nothing to install. Erlang/OTP was already installed by the step above.

---

## Configuration

### 1. Accounts (data.txt)

Fill `data.txt` with the Telegram WebApp `initData` of each account, one per line:

```
query_id=AAH...&user=%7B%22id%22%3A123%7D&auth_date=...&hash=abc123
query_id=AAH...&user=%7B%22id%22%3A456%7D&auth_date=...&hash=def456
```

> `initData` can be obtained from the browser DevTools when opening the Fruit Cut Miniapp on Telegram Web. The whole WebView URL is accepted too, and the bot strips it down 

### 2. Proxy (proxy.txt)

Fill `proxy.txt` with proxies, one per line (optional, leave empty to run without proxy):

```
host:port
host:port:user:pass
http://user:pass@host:port
```

Proxies are assigned to accounts by index in round-robin order, and proxy credentials are masked in the log output.

### 3. Bot Settings (config.json)

`sleep_seconds` controls how long the bot waits between cycles. Accounts are processed back to back with no delay in between.

```json
{
  "settings": {
    "sleep_seconds": 3600
  }
}
```

---

## Running the Bot

**Linux / macOS:**

```bash
elixir --erl "+Bd" bot.exs
```

**Windows:**

```cmd
elixir --erl "+Bc" bot.exs
```

Or just double click `run_pc.bat`, which runs the Windows command above.

---

## Features

### Account State
At the start of every account the bot signs in with that account `initData`, sends it in the `x-telegram-init-data` header and logs the account name together with the current fruit coin balance and level. An account whose `initData` is refused is reported and skipped before any other request is sent.

### Treasure Box
The treasure box is claimed once per account and the reward the server credits is logged. A box the server has already granted, or one that is still inside its cooldown, is reported as its own line instead of being retried.

### Reward Task Ads
The reward task ad the server offers is claimed once per account: the bot asks for a session first and then claims that session, and the amount the server credits is logged. A quota that is already full for the day, or a session the server refuses because the requests came too close together, is reported as such and the rest of the cycle keeps moving.

### Ad Networks
The GigaPub and the Monetag slot are claimed on the same account turn without opening the ad player. The session for both networks is opened right after the sign in, the rest of the account turn runs on top of it, and the claim is sent once that work is done so the server sees a session that is old enough to be accepted. Every slot is then repeated on the same turn, opening a fresh session each round, until the server answers that the daily quota is full, so a cycle drains the whole daily allowance instead of a single ad. The Adsgram Daily slot is filled by running the ad view itself: the bot asks the server for a session, requests a banner from the Adsgram endpoint with the account `signature` and `data_check_string` taken from the same `initData`, fires the render, show and reward trackers the banner carries, and claims the session once the network postback has landed. A network whose daily quota is already full, a session the server answers with a request to slow down, and a network that wants a real view postback are each reported as their own line and the account keeps walking. An Adsgram answer that carries no banner at all is a fill miss, so the round is repeated while the slot still has room and the miss is only stated once the rounds run out.

### Game Reward
The play reward is claimed from the play clock the server keeps, not from a timer in the bot. The server only credits play time while the account keeps pinging inside the same window, so the bot pings the play endpoint between the steps of an account turn and once every thirty seconds of the cycle countdown, and the accrued time carries over between cycles. Once the accrued time passes the claim mark the bot opens a game ad session, runs the Adsgram ad view for it, and claims the reward, retrying the claim while the network postback is still on its way. The reward, the balance and the remaining play time are logged, and a claim the server refuses is stated as its own line.

### Slice Arena
A slice arena round is opened and claimed right away, and the reward the server credits is logged together with the total number of slices the account has cut. A round the server reports as still inside its cooldown is stated plainly instead of being retried, and a session the server rejects as not yet playable is claimed again until the server accepts it or reports a real refusal.

### Task Rewards
The task list is pulled once per account and every task the account has not completed yet is claimed. A task the server credits is logged with its reward, and a task the server refuses, for example a channel the account has not joined yet, is reported as its own line so the rest of the list keeps moving.

### Multi Account
All accounts in `data.txt` are processed sequentially within every cycle. Each account block starts with its own proxy line, and blocks are separated by one blank line so the mapping between an account and its egress is auditable in the log. The cycle number is logged at the start of each round.

### Proxy Support
Proxies are loaded from `proxy.txt` and assigned to accounts by position in round-robin order. Proxy credentials are masked in log output. Running without proxies is fully supported.

### Auto Countdown
After all accounts complete a cycle, the bot displays a live `HH:MM:SS` countdown until the next cycle starts. The countdown also keeps the play clock of the last account alive by pinging the play endpoint every thirty seconds, so the game reward keeps accruing while the bot waits.

---

## File Structure

```text
FruitCutBot-Elixir/
├── bot.exs         # Main bot, daily cycle automation
├── config.json     # Sleep duration between cycles
├── data.txt        # Account initData, one per line
├── proxy.txt       # Proxy list, one per line (optional)
├── run_pc.bat      # Launcher for Windows
├── LICENSE         # License file
└── utils/
    ├── banner.ex   # Banner display on startup
    └── json.ex     # JSON encoder and decoder
```

---

## Disclaimer

This tool is built for educational and technical exploration purposes. Use it wisely and at your own responsibility.

---

<div align="center">
<img width="100%" alt="footer" src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer"/>
</div>
