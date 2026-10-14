Code.require_file("utils/json.ex", __DIR__)
Code.require_file("utils/banner.ex", __DIR__)

defmodule FruitCutBot do
  @moduledoc false

  @my_project "Fruit Cut"
  @base_url "https://fruit-cut-eight.vercel.app"
  @referral "6004380466"

  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[91m"
  @green "\e[92m"
  @yellow "\e[93m"

  def run do
    :logger.set_primary_config(:level, :error)
    install_signal_handler()

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    Banner.set_title(@my_project)
    Banner.show_banner(@my_project)

    accounts = load_lines("data.txt")

    if accounts == [] do
      red("File data.txt is empty, please add your initData entries")
      System.halt(1)
    end

    proxies = load_lines("proxy.txt")
    settings = load_settings()

    loop(accounts, proxies, settings, 1)
  end

  defp loop(accounts, proxies, settings, cycle) do
    yellow("Starting automation cycle number #{cycle}")

    last =
      accounts
      |> Enum.with_index()
      |> Enum.reduce(nil, fn {line, index}, acc ->
        if index > 0, do: IO.puts("")

        proxy = proxy_for(proxies, index)

        case proxy do
          nil -> yellow("Running without proxy for this account")
          entry -> yellow("Using proxy #{mask_proxy(entry)}")
        end

        try do
          process_account(line, index + 1, proxy)
        rescue
          _error ->
            red("Account #{index + 1} was skipped after an error")
            acc
        end
      end)

    yellow("All accounts processed for cycle number #{cycle}")

    countdown(sleep_seconds(settings), "Next cycle starts in", last)

    Banner.show_banner(@my_project)

    loop(accounts, proxies, settings, cycle + 1)
  end

  defp process_account(line, label, proxy) do
    case init_data_of(line) do
      {:ok, init, profile} ->
        state = %{
          init: init,
          label: label,
          proxy: proxy,
          id: get(profile, "id", 0),
          username: get(profile, "username", ""),
          first_name: get(profile, "firstName", ""),
          user: %{}
        }

        case sign_in(state, proxy) do
          {:ok, data} ->
            user = get(data, "user", %{})

            handle =
              shorten(clean_text(get(profile, "username", state.first_name), "account"), "account", 16)

            state =
              state
              |> Map.put(:handle, handle)
              |> Map.put(:user, user)

            green(
              "Signed in #{handle} fruit coin #{money(get(user, "fruitCoin", 0))} level #{count(get(user, "level", 0))}"
            )

            state
            |> process_game(proxy)
            |> open_ad_sessions(proxy)
            |> process_game(proxy)
            |> process_tasks(proxy)
            |> process_gift(proxy)
            |> process_game(proxy)
            |> process_ad_task(proxy)
            |> process_slash(proxy)
            |> claim_ad_slots(proxy)
            |> process_game(proxy)
            |> claim_daily_slot(proxy)
            |> process_game(proxy)
            |> process_sync(proxy)
            |> report_game(proxy)

          {:error, reason} ->
            red("Account #{label} refused with #{short_reason(reason)}")
        end

      :error ->
        red("Account #{label} line has no usable initData")
    end
  end

  defp sign_in(state, proxy) do
    payload = %{
      "deviceId" => device_id(state),
      "referredBy" => @referral,
      "photoUrl" => nil
    }

    post_api(state, "/api/auth", payload, proxy)
  end

  defp device_id(state) do
    digest =
      :crypto.hash(:md5, "fruit-cut:" <> stringify(state.id))
      |> Base.encode16(case: :lower)

    "dv2_" <> digest
  end

  defp process_tasks(state, proxy) do
    case get_api(state, "/api/verify_task", proxy) do
      {:ok, data} ->
        done = get(state.user, "completedTasks", [])

        data
        |> get("tasks", [])
        |> Enum.reject(fn task -> Enum.member?(done, get(task, "id", "")) end)
        |> Enum.each(fn task -> claim_task(state, task, proxy) end)

      {:error, reason} ->
        yellow("Task list refused with #{short_reason(reason)}")
    end

    state
  end

  defp claim_task(state, task, proxy) do
    payload = %{"telegramId" => state.id, "taskId" => get(task, "id", "")}
    label = shorten(clean_text(get(task, "title", "task"), "task"), "task", 26)
    reward = whole(get(task, "rewardFc", 0), 0)

    case post_api(state, "/api/verify_task", payload, proxy) do
      {:ok, data} ->
        if get(data, "success", false) do
          green("Task #{label} credited #{money(reward)} fruit coin")
        else
          yellow("Task #{label} refused with #{short_reason(task_reason(data))}")
        end

      {:error, reason} ->
        yellow("Task #{label} refused with #{short_reason(reason)}")
    end
  end

  defp task_reason(data) do
    first_text([get(data, "error", ""), get(data, "message", "")], "reason")
  end

  defp process_gift(state, proxy) do
    case post_api(state, "/api/game_claim", %{"action" => "claim_daily_gift"}, proxy) do
      {:ok, data} ->
        if get(data, "success", false) do
          green("Treasure box credited #{money(get(data, "reward", 0))} fruit coin")
        else
          yellow("Treasure box is on cooldown")
        end

      {:error, reason} ->
        yellow("Treasure box refused with #{short_reason(reason)}")
    end

    state
  end

  defp process_ad_task(state, proxy) do
    ad_task_round(state, proxy)
    state
  end

  defp ad_task_round(state, proxy) do
    payload = %{"action" => "request_session", "network" => "adsgramTask"}

    case post_api(state, "/api/ads", payload, proxy) do
      {:ok, data} ->
        case get(data, "sessionId", "") do
          "" ->
            ad_session_reason(data)
            :stop

          session ->
            claim_ad_task(state, session, proxy)
        end

      {:error, reason} ->
        yellow("Task ad session refused with #{short_reason(reason)}")
        :stop
    end
  end

  defp ad_session_reason(data) do
    case get(data, "message", "") do
      "daily_limit_reached" ->
        yellow("Task ad quota is full today")

      other ->
        yellow("Task ad was refused with #{short_reason(other)}")
    end
  end

  defp claim_ad_task(state, session, proxy) do
    payload = %{"action" => "adsgramTask", "sessionId" => session}

    case post_api(state, "/api/ads", payload, proxy) do
      {:ok, data} ->
        if get(data, "success", false) do
          green("Task ad credited #{money(get(data, "rewardFc", 0))} fruit coin")
          :credited
        else
          ad_claim_reason("Task", data)
          :stop
        end

      {:error, reason} ->
        yellow("Task ad was refused with #{short_reason(reason)}")
        :stop
    end
  end

  defp open_ad_sessions(state, proxy) do
    state
    |> Map.put(:gigapub_ad, open_ad_session(state, proxy, "gigapub"))
    |> Map.put(:monetag_ad, open_ad_session(state, proxy, "monetag"))
  end

  defp watch_adsgram(state, proxy) do
    case ads_get(state, daily_adv_url(state), proxy) do
      {:ok, 200, body} ->
        case YuurisanJSON.decode(body) do
          {:ok, data} -> play_daily_banners(state, get(data, "banners", []), proxy)
          _other -> {:error, "unreadable ad response"}
        end

      {:ok, status, body} ->
        {:error, ad_error_of(body, status)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp play_daily_banners(state, banners, proxy) when is_list(banners) and banners != [] do
    Enum.each(banners, fn banner ->
      tracks = daily_tracks(banner)
      ping_daily_track(state, proxy, get(tracks, "render", ""))
      ping_daily_track(state, proxy, get(tracks, "show", ""))
    end)

    tracks = daily_tracks(List.last(banners))
    ping_daily_track(state, proxy, get(tracks, "reward", ""))

    :ok
  end

  defp play_daily_banners(_state, _banners, _proxy), do: {:error, "no ad banner available"}

  defp daily_tracks(banner) do
    banner
    |> get("banner", %{})
    |> get("trackings", [])
    |> Enum.reduce(%{}, fn track, acc ->
      Map.put(acc, get(track, "name", ""), get(track, "value", ""))
    end)
  end

  defp ping_daily_track(_state, _proxy, ""), do: :ok

  defp ping_daily_track(state, proxy, url) do
    ads_get(state, url, proxy)
    :ok
  end

  defp daily_adv_url(state) do
    params = [
      {"envType", "telegram"},
      {"blockId", "53454"},
      {"platform", "Win32"},
      {"language", "en"},
      {"is_premium", "false"},
      {"top_domain", URI.parse(@base_url).host},
      {"signature", init_field(state, "signature")},
      {"data_check_string", daily_check_string(state)},
      {"sdk_version", "2.2.5"},
      {"tg_id", to_string(state.id)},
      {"tg_platform", "android"},
      {"tma_version", "9.6"},
      {"request_id", daily_request_id()},
      {"raw", init_field(state, "hash")}
    ]

    query =
      params
      |> Enum.map(fn {key, value} -> key <> "=" <> URI.encode_www_form(value) end)
      |> Enum.join("&")

    "https://api.adsgram.ai/adv" <> "?" <> query
  end

  defp daily_check_string(state) do
    state.init
    |> init_pairs()
    |> Enum.reject(fn {key, _value} -> key == "hash" or key == "signature" end)
    |> Enum.sort()
    |> Enum.map(fn {key, value} -> key <> "=" <> value end)
    |> Enum.join("\n")
    |> Base.encode64()
  end

  defp init_field(state, key) do
    state.init
    |> init_pairs()
    |> Enum.find_value("", fn
      {^key, value} -> value
      _other -> nil
    end)
  end

  defp init_pairs(init) do
    init
    |> URI.decode_query()
    |> Enum.to_list()
  rescue
    _error -> []
  end

  defp daily_request_id do
    1..26
    |> Enum.map(fn _index -> Enum.random(0..9) end)
    |> Enum.join()
  end

  defp claim_ad_slots(state, proxy) do
    state
    |> claim_ad_slot(proxy, :gigapub_ad, "gigapub", "GigaPub")
    |> claim_ad_slot(proxy, :monetag_ad, "monetag", "Monetag")
  end

  defp claim_ad_slot(state, proxy, key, network, name) do
    session =
      case Map.get(state, key) do
        {:session, existing} -> {:session, existing}
        _other -> open_ad_session(state, proxy, network)
      end

    case session do
      {:session, sid} ->
        finish_ad_round(state, proxy, network, name, sid)

      {:refused, message} ->
        ad_claim_reason(name, %{"message" => message})
        state
    end
  end

  defp finish_ad_round(state, proxy, network, name, sid) do
    payload = %{"action" => network, "sessionId" => sid}

    case post_ad_claim(state, proxy, payload, name) do
      :retryable -> ad_retry(state, proxy, network, name, 0)
      _other -> state
    end
  end

  defp ad_retry(state, proxy, network, name, tries) when tries < 3 do
    process_game(state, proxy)

    case open_ad_session(state, proxy, network) do
      {:session, sid} ->
        case post_ad_claim(state, proxy, %{"action" => network, "sessionId" => sid}, name) do
          :retryable -> ad_retry(state, proxy, network, name, tries + 1)
          _other -> state
        end

      {:refused, _message} ->
        state
    end
  end

  defp ad_retry(state, _proxy, _network, name, _tries) do
    yellow("#{name} ad window did not open in this cycle")
    state
  end

  defp post_ad_claim(state, proxy, payload, name) do
    case post_api(state, "/api/ads", payload, proxy) do
      {:ok, data} ->
        cond do
          get(data, "success", false) ->
            green("#{name} ad credited #{money(get(data, "rewardFc", 0))} fruit coin")
            :credited

          get(data, "retryable", false) ->
            :retryable

          true ->
            ad_claim_reason(name, data)
            :stop
        end

      {:error, reason} ->
        yellow("#{name} ad was refused with #{short_reason(reason)}")
        :stop
    end
  end

  defp claim_daily_slot(state, proxy) do
    {state, outcome} =
      Enum.reduce_while(1..10, {state, :retry}, fn _round, {acc, _out} ->
        case claim_daily_round(acc, proxy) do
          :credited -> {:cont, {acc, :credited}}
          :retry -> {:cont, {acc, :retry}}
          :stop -> {:halt, {acc, :stop}}
        end
      end)

    if outcome == :retry, do: yellow("Adsgram Daily ad had no fill in this cycle")
    state
  end

  defp claim_daily_round(state, proxy) do
    case open_ad_session(state, proxy, "adsgramDaily") do
      {:session, session} ->
        case watch_adsgram(state, proxy) do
          :ok -> post_daily_claim(state, proxy, session)
          {:error, reason} -> retry_or_stop("Adsgram Daily", reason)
        end

      {:refused, message} ->
        ad_claim_reason("Adsgram Daily", %{"message" => message})
        :stop
    end
  end

  defp retry_or_stop(name, reason) do
    if String.contains?(reason, "available ad") do
      :retry
    else
      yellow("#{name} ad was refused with #{short_reason(reason)}")
      :stop
    end
  end

  defp post_daily_claim(state, proxy, session) do
    payload = %{"action" => "adsgramDaily", "sessionId" => session}

    case post_api(state, "/api/ads", payload, proxy) do
      {:ok, data} ->
        cond do
          get(data, "success", false) ->
            green("Adsgram Daily ad credited #{money(get(data, "rewardFc", 0))} fruit coin")
            :credited

          get(data, "retryable", false) ->
            yellow("Adsgram Daily ad is waiting for the view to settle")
            :credited

          true ->
            ad_claim_reason("Adsgram Daily", data)
            :stop
        end

      {:error, reason} ->
        yellow("Adsgram Daily ad was refused with #{short_reason(reason)}")
        :stop
    end
  end

  defp ping_game(state, proxy) do
    post_api(state, "/api/ads", %{"action" => "game_ping", "gameId" => "fruit_cut"}, proxy)
  end

  defp process_game(state, proxy) do
    case ping_game(state, proxy) do
      {:ok, data} ->
        if get(data, "claimable", false), do: claim_game_reward(state, proxy)

      {:error, _reason} ->
        :ok
    end

    state
  end

  defp report_game(state, proxy) do
    case ping_game(state, proxy) do
      {:ok, data} ->
        if get(data, "claimable", false) do
          claim_game_reward(state, proxy)
        else
          left = max(whole(get(data, "claimMs", 0), 0) - whole(get(data, "playMs", 0), 0), 0)
          yellow("Game reward needs #{format_duration(div(left, 1000))} more of play time")
        end

      {:error, reason} ->
        yellow("Game reward check was refused with #{short_reason(reason)}")
    end

    state
  end

  defp claim_game_reward(state, proxy) do
    payload = %{"action" => "request_session", "network" => "gameAd", "provider" => "adsgram"}

    case post_api(state, "/api/ads", payload, proxy) do
      {:ok, data} ->
        case get(data, "sessionId", "") do
          "" -> ad_claim_reason("Game reward", data)
          session -> finish_game_reward(state, proxy, session)
        end

      {:error, reason} ->
        yellow("Game reward ad was refused with #{short_reason(reason)}")
    end
  end

  defp finish_game_reward(state, proxy, session) do
    case watch_adsgram(state, proxy) do
      :ok -> post_game_claim(state, proxy, session, 0)
      {:error, reason} -> yellow("Game reward ad was refused with #{short_reason(reason)}")
    end
  end

  defp post_game_claim(state, proxy, session, tries) do
    payload = %{"action" => "gameAd", "sessionId" => session}

    case post_api(state, "/api/ads", payload, proxy) do
      {:ok, data} ->
        cond do
          get(data, "success", false) ->
            green("Game reward credited #{money(get(data, "rewardFc", 0))} fruit coin")

          get(data, "retryable", false) and tries < 12 ->
            ping_game(state, proxy)
            post_game_claim(state, proxy, session, tries + 1)

          true ->
            ad_claim_reason("Game reward", data)
        end

      {:error, reason} ->
        yellow("Game reward ad was refused with #{short_reason(reason)}")
    end
  end

  defp ad_error_of(body, status) do
    case YuurisanJSON.decode(body) do
      {:ok, data} ->
        first_text([get(data, "error", ""), get(data, "message", "")], "HTTP #{status}")

      _other ->
        "HTTP #{status}"
    end
  end

  defp open_ad_session(state, proxy, network) do
    payload = %{"action" => "request_session", "network" => network}

    case post_api(state, "/api/ads", payload, proxy) do
      {:ok, data} ->
        case get(data, "sessionId", "") do
          "" -> {:refused, task_reason(data)}
          session -> {:session, session}
        end

      {:error, reason} ->
        {:refused, reason}
    end
  end

  defp ad_claim_reason(name, data) do
    case task_reason(data) do
      "daily_limit_reached" ->
        yellow("#{name} ad quota is full today")

      "too_fast" ->
        yellow("#{name} ad window is not open yet")

      "waiting_postback" ->
        yellow("#{name} ad needs a real view postback")

      other ->
        yellow("#{name} ad was refused with #{short_reason(other)}")
    end
  end

  defp process_slash(state, proxy) do
    case post_api(state, "/api/slash", %{"action" => "start"}, proxy) do
      {:ok, data} ->
        case get(data, "sessionId", "") do
          "" -> yellow("Slice arena refused to start with #{short_reason(task_reason(data))}")
          session -> claim_slash(state, session, proxy, 0)
        end

      {:error, reason} ->
        yellow("Slice arena refused to start with #{short_reason(reason)}")
    end

    state
  end

  defp claim_slash(state, session, proxy, tries) do
    payload = %{"action" => "claim", "sessionId" => session}

    case post_api(state, "/api/slash", payload, proxy) do
      {:ok, data} ->
        cond do
          get(data, "success", false) ->
            green(
              "Slice arena credited #{money(get(data, "reward", 0))} fruit coin, slices #{count(get(data, "totalSlices", 0))}"
            )

          get(data, "error", "") == "invalid_session" and tries < 4 ->
            claim_slash(state, session, proxy, tries + 1)

          get(data, "error", "") == "on_cooldown" ->
            yellow("Slice arena is on cooldown")

          true ->
            yellow("Slice arena was refused with #{short_reason(task_reason(data))}")
        end

      {:error, reason} ->
        yellow("Slice arena was refused with #{short_reason(reason)}")
    end
  end

  defp process_sync(state, proxy) do
    case post_api(state, "/api/init", %{"syncOnly" => true}, proxy) do
      {:ok, data} ->
        user = get(data, "user", %{})

        green(
          "Balance fruit coin #{money(get(user, "fruitCoin", 0))} level #{count(get(user, "level", 0))} slices #{count(get(user, "totalSlices", 0))}"
        )

      {:error, reason} ->
        yellow("Balance check refused with #{short_reason(reason)}")
    end

    state
  end

  defp post_api(state, path, payload, proxy) do
    request(state, path, :post, to_charlist(YuurisanJSON.encode(payload)), proxy)
  end

  defp get_api(state, path, proxy) do
    request(state, path, :get, ~c"", proxy)
  end

  defp ads_get(_state, url, proxy) do
    {profile, auth} = proxy_setup(proxy)

    headers = [
      {~c"accept", ~c"application/json, text/plain, */*"},
      {~c"accept-language", ~c"en-US,en;q=0.9"},
      {~c"origin", String.to_charlist(@base_url)},
      {~c"referer", String.to_charlist(@base_url <> "/")},
      {~c"user-agent",
       ~c"Mozilla/5.0 (Linux; Android 16; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.18 Mobile Safari/537.36 Telegram-Android/12.8.1 (Oppo CPH2631; Android 16; SDK 36; HIGH)"},
      {~c"x-color-scheme", ~c"dark"},
      {~c"x-is-fullscreen", ~c"false"}
    ]

    options = [ssl: [verify: :verify_none], timeout: 30_000, connect_timeout: 15_000] ++ auth

    case :httpc.request(
           :get,
           {String.to_charlist(url), headers},
           options,
           [body_format: :binary],
           profile
         ) do
      {:ok, {{_version, status, _reason}, _headers, response}} -> {:ok, status, to_string(response)}
      {:error, reason} -> {:error, stringify(reason)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp request(state, path, method, body, proxy) do
    {profile, auth} = proxy_setup(proxy)
    url = String.to_charlist(@base_url <> path)

    headers =
      [
        {~c"accept", ~c"application/json, text/plain, */*"},
        {~c"accept-language", ~c"en-US,en;q=0.9"},
        {~c"origin", String.to_charlist(@base_url)},
        {~c"referer", String.to_charlist(@base_url <> "/?tgWebAppStartParam=" <> @referral)},
        {~c"user-agent",
         ~c"Mozilla/5.0 (Linux; Android 16; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.18 Mobile Safari/537.36 Telegram-Android/12.8.1 (Oppo CPH2631; Android 16; SDK 36; HIGH)"},
        {~c"x-telegram-init-data", to_charlist(state.init)}
      ] ++ content_header(method)

    options = [ssl: [verify: :verify_none], timeout: 30_000, connect_timeout: 15_000] ++ auth

    handle(
      :httpc.request(
        method,
        call_body(method, url, headers, body),
        options,
        [body_format: :binary],
        profile
      )
    )
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp content_header(:get), do: []
  defp content_header(_method), do: [{~c"content-type", ~c"application/json"}]

  defp call_body(:get, url, headers, _body), do: {url, headers}
  defp call_body(_method, url, headers, body), do: {url, headers, ~c"application/json", body}

  defp handle({:ok, {{_version, status, _reason}, _headers, response}})
       when status >= 200 and status < 300 do
    decode_json(to_string(response))
  end

  defp handle({:ok, {{_version, status, _reason}, _headers, response}}) do
    {:error, error_of(to_string(response), status)}
  end

  defp handle({:error, reason}), do: {:error, stringify(reason)}

  defp error_of(raw, status) do
    case decode_json(raw) do
      {:ok, data} ->
        first_text(
          [get(data, "title", ""), get(data, "error", ""), get(data, "message", "")],
          "HTTP #{status}"
        )

      {:error, _reason} ->
        "HTTP #{status}"
    end
  end

  defp first_text(values, fallback) do
    case Enum.find(values, fn value -> is_binary(value) and value != "" end) do
      nil -> fallback
      text -> text
    end
  end

  defp decode_json(raw) do
    case YuurisanJSON.decode(raw) do
      {:ok, %{} = data} -> {:ok, data}
      _other -> {:error, "unreadable response"}
    end
  end

  defp init_data_of(line) do
    value =
      line
      |> String.trim()
      |> String.trim_leading("\"")
      |> String.trim_trailing("\"")
      |> extract_init_data()

    if value == "" do
      :error
    else
      try do
        case URI.decode_query(value) do
          %{"user" => raw} ->
            case YuurisanJSON.decode(raw) do
              {:ok, %{"id" => _id} = profile} -> {:ok, value, profile}
              _other -> :error
            end

          _other ->
            :error
        end
      rescue
        _error -> :error
      end
    end
  end

  defp extract_init_data(value) do
    if String.contains?(value, "tgWebAppData=") do
      value
      |> String.split("tgWebAppData=")
      |> List.last()
      |> String.split("&tgWebApp")
      |> List.first()
      |> URI.decode_www_form()
    else
      value
      |> String.trim_leading("?")
      |> String.trim_leading("#")
      |> String.split("&tgUplineId=")
      |> List.first()
    end
  end

  defp proxy_setup(nil), do: {:default, []}

  defp proxy_setup(line) do
    case parse_proxy(line) do
      {host, port, user, pass} -> proxy_profile(host, port, user, pass)
      {host, port} -> proxy_profile(host, port, "", "")
      nil -> {:default, []}
    end
  end

  defp proxy_profile(host, port, user, pass) do
    name = String.to_atom("proxy_#{host}_#{port}")
    address = {String.to_charlist(host), port}

    case :inets.start(:httpc, profile: name) do
      {:ok, _pid} ->
        :httpc.set_options([proxy: {address, []}, https_proxy: {address, []}], name)

      {:error, {:already_started, _pid}} ->
        :ok

      _other ->
        :ok
    end

    case user do
      "" -> {name, []}
      _ -> {name, [proxy_auth: {String.to_charlist(user), String.to_charlist(pass)}]}
    end
  end

  defp parse_proxy(line) do
    value =
      line
      |> String.trim()
      |> String.replace_prefix("http://", "")
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("socks5://", "")

    case String.split(value, "@") do
      [credentials, host_part] ->
        case String.split(credentials, ":") do
          [user, pass] -> with_host_port(host_part, user, pass)
          _other -> with_host_port(host_part, "", "")
        end

      [host_part] ->
        case String.split(host_part, ":") do
          [host, port] -> with_port(host, port)
          [host, port, user, pass] -> with_port_creds(host, port, user, pass)
          _other -> nil
        end
    end
  end

  defp with_host_port(host_part, user, pass) do
    case String.split(host_part, ":") do
      [host, port] -> with_port_creds(host, port, user, pass)
      _other -> nil
    end
  end

  defp with_port(host, port) do
    case Integer.parse(port) do
      {number, ""} -> {host, number}
      _other -> nil
    end
  end

  defp with_port_creds(host, port, user, pass) do
    case Integer.parse(port) do
      {number, ""} -> {host, number, user, pass}
      _other -> nil
    end
  end

  defp mask_proxy(line) do
    case parse_proxy(line) do
      {host, port, _user, _pass} -> "http://user:pass@#{mask_host(host)}:#{port}"
      {host, port} -> "http://user:pass@#{mask_host(host)}:#{port}"
      nil -> "http://user:pass@***:***"
    end
  end

  defp mask_host(host) do
    parts = String.split(host, ".")

    case parts do
      [a, _b, _c, d] ->
        "#{a}*****#{d}"

      _other ->
        if String.length(host) > 4 do
          String.slice(host, 0, 2) <> "*****" <> String.slice(host, -2, 2)
        else
          "***"
        end
    end
  end

  defp proxy_for([], _index), do: nil
  defp proxy_for(proxies, index), do: Enum.at(proxies, rem(index, length(proxies)))

  defp load_lines(name) do
    case File.read(Path.join(__DIR__, name)) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp load_settings do
    case File.read(Path.join(__DIR__, "config.json")) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, %{"settings" => settings}} when is_map(settings) -> settings
          _other -> %{}
        end

      {:error, _reason} ->
        %{}
    end
  end

  defp sleep_seconds(settings), do: whole(get(settings, "sleep_seconds", 3600), 3600)

  defp install_signal_handler do
    handler = fn ->
      IO.write("\n" <> @red <> @bold <> "Script stopped by user" <> @reset <> "\n")
      System.halt(0)
    end

    for signal <- [:sigterm, :sighup, :sigquit] do
      try do
        System.trap_signal(signal, handler)
      rescue
        _error -> :ok
      end
    end
  end

  defp clean_text(value, fallback) do
    text =
      value
      |> stringify()
      |> String.replace(
        ["[", "]", "|", "#", "!", "@", "$", "%", "^", "&", "*", "(", ")", "-"],
        " "
      )

    case String.split(text) |> Enum.join(" ") do
      "" -> fallback
      cleaned -> cleaned
    end
  end

  defp short_reason(reason), do: shorten(clean_text(reason, "reason"), "reason", 26)

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp stringify({:failed_connect, _reason}), do: "no network connection"
  defp stringify({:failed_connect, _reason, _host}), do: "no network connection"
  defp stringify({:timeout, _reason}), do: "the request timed out"
  defp stringify(value), do: inspect(value)

  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp get(_other, _key, default), do: default

  defp whole(value, _fallback) when is_integer(value), do: value
  defp whole(value, _fallback) when is_float(value), do: trunc(value)
  defp whole(_value, fallback), do: fallback

  defp money(value) do
    value |> stringify() |> String.replace(",", "") |> shorten("0", 9)
  end

  defp count(value) do
    value |> stringify() |> shorten("0", 8)
  end

  defp shorten(value, fallback, limit) do
    text = value |> to_string() |> String.trim()

    case String.slice(text, 0, limit) do
      "" -> fallback
      short -> String.trim(short)
    end
  end

  defp countdown(seconds, label, state) do
    left = max(trunc(seconds), 0)

    if left >= 1 do
      width = frame(label, left, 0)
      tick(left, label, width, state)
    end
  end

  defp tick(0, _label, width, _state) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
  end

  defp tick(left, label, width, state) do
    width = frame(label, left, width)
    if rem(left, 30) == 0, do: play_tick(state, width)
    :timer.sleep(1000)
    tick(left - 1, label, width, state)
  end

  defp play_tick(state, width) when is_map(state) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
    process_game(state, Map.get(state, :proxy))
  end

  defp play_tick(_state, _width), do: :ok

  defp frame(label, left, width) do
    text = label <> " " <> format_duration(left)
    IO.write("\r" <> @yellow <> @bold <> text <> @reset)
    max(width, String.length(text))
  end

  defp format_duration(total) do
    days = div(total, 86_400)
    hours = div(rem(total, 86_400), 3600)
    minutes = div(rem(total, 3600), 60)
    seconds = rem(total, 60)

    if days > 0 do
      pad(days) <> ":" <> pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    end
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp green(message), do: IO.puts(@green <> @bold <> message <> @reset)
  defp yellow(message), do: IO.puts(@yellow <> @bold <> message <> @reset)
  defp red(message), do: IO.puts(@red <> @bold <> message <> @reset)
end

FruitCutBot.run()
