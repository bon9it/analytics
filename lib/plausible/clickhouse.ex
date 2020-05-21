defmodule Plausible.Clickhouse do
  def all(query) do
    {q, params} = Ecto.Adapters.SQL.to_sql(:all, Plausible.Repo, query)
    q = String.replace(q, ~r/\$[0-9]+/, "?")
    res = Clickhousex.query!(:clickhouse, q, params, log: {Plausible.Clickhouse, :log, []})
    Enum.map(res.rows, fn row ->
      Enum.zip(res.columns, row)
      |> Enum.into(%{})
    end)
  end

  def insert_events(events) do
    insert = """
    INSERT INTO events (name, timestamp, domain, user_id, session_id, hostname, pathname, referrer, referrer_source, initial_referrer, initial_referrer_source, country_code, screen_size, browser, operating_system)
    VALUES
    """ <> String.duplicate(" (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?),", length(events))

    args = Enum.reduce(events, [], fn event, acc ->
      [event.name, event.timestamp, event.domain, event.user_id, event.session_id, event.hostname, escape_quote(event.pathname), event.referrer || "", event.referrer_source || "", event.initial_referrer || "", event.initial_referrer_source || "", event.country_code || "", event.screen_size || "", event.browser || "", event.operating_system || ""] ++ acc
    end)

    Clickhousex.query(:clickhouse, insert, args, log: {Plausible.Clickhouse, :log, []})
  end

  def insert_sessions(sessions) do
    insert = """
    INSERT INTO sessions (sign, session_id, domain, user_id, timestamp, hostname, start, is_bounce, entry_page, exit_page, events, pageviews, duration, referrer, referrer_source, country_code, screen_size, browser, operating_system)
    VALUES
    """ <> String.duplicate(" (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?),", Enum.count(sessions))

    args = Enum.reduce(sessions, [], fn session, acc ->
      [session.sign, session.session_id, session.domain, session.user_id, session.timestamp, session.hostname, session.start, session.is_bounce && 1 || 0, session.entry_page, session.exit_page, session.events, session.pageviews, session.duration, session.referrer || "", session.referrer_source || "", session.country_code || "", session.screen_size || "", session.browser || "", session.operating_system || ""] ++ acc
    end)

    Clickhousex.query(:clickhouse, insert, args, log: {Plausible.Clickhouse, :log, []})
  end

  def escape_quote(s) do
    String.replace(s, "'", "''")
  end

  def log(query) do
    require Logger
    timing = System.convert_time_unit(query.connection_time, :native, :millisecond)
    case query.result do
      {:ok, _q, _res} ->
        Logger.info("Clickhouse query OK db=#{timing}ms")
      {:error, e} ->
        Logger.error("Clickhouse query ERROR")
        Logger.error(inspect e)
    end

    Logger.debug(fn ->
      statement = String.replace(query.query.statement, "\n", " ")
      "#{statement} #{inspect query.params}"
    end)
  end
end