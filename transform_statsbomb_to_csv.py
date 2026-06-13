"""Transform StatsBomb Open Data JSON files into clean CSV tables."""

from __future__ import annotations

import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

import pandas as pd


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Use None to process every available competition or match.
MAX_COMPETITIONS: int | None = None
MAX_MATCHES: int | None = None
USE_EVENTS = True
SHOW_PREVIEW = True
PREVIEW_ROWS = 5

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = BASE_DIR / "data_clean"


def warn(message: str) -> None:
    """Print a visible warning without interrupting the transformation."""
    print(f"[WARNING] {message}")


def load_json(path: Path) -> Any | None:
    """Load one JSON file, returning None when it is missing or invalid."""
    if not path.exists():
        warn(f"No se encontró el archivo: {path}")
        return None

    try:
        with path.open("r", encoding="utf-8") as file:
            return json.load(file)
    except (OSError, json.JSONDecodeError) as exc:
        warn(f"No se pudo leer {path}: {exc}")
        return None


def to_int(value: Any) -> int | None:
    """Convert StatsBomb IDs to integers and reject invalid values."""
    try:
        if value is None or value == "":
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def clean_string(value: Any) -> str | None:
    """Normalize empty text values to NULL-compatible None values."""
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None


def nested_name(value: Any) -> str | None:
    """Extract a name from a common StatsBomb nested object."""
    if isinstance(value, dict):
        return clean_string(value.get("name"))
    return clean_string(value)


def normalize_date(value: Any) -> str | None:
    """Return dates in YYYY-MM-DD format, or None when unavailable."""
    text = clean_string(value)
    if text is None:
        return None

    # StatsBomb dates normally arrive as ISO strings. The fallback formats
    # make the transform tolerant of small variations in local datasets.
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).date().isoformat()
    except ValueError:
        for date_format in ("%Y/%m/%d", "%d/%m/%Y", "%m/%d/%Y"):
            try:
                return datetime.strptime(text, date_format).date().isoformat()
            except ValueError:
                continue
    warn(f"Fecha no reconocida: {text}")
    return None


def first_not_null(old: Any, new: Any) -> Any:
    """Keep the existing value unless it is empty."""
    return old if old not in (None, "") else new


def upsert_team(teams: dict[int, dict[str, Any]], team: dict[str, Any]) -> None:
    """Insert a team or enrich its existing row with non-empty values."""
    team_id = to_int(team.get("team_id"))
    if team_id is None:
        return

    candidate = {
        "team_id": team_id,
        "team_name": clean_string(team.get("team_name")),
        "country": clean_string(team.get("country")) or "Unknown",
        "city": clean_string(team.get("city")),
        "stadium": clean_string(team.get("stadium")),
        "founded_year": to_int(team.get("founded_year")),
    }
    if team_id not in teams:
        teams[team_id] = candidate
        return

    for key in ("team_name", "country", "city", "stadium", "founded_year"):
        teams[team_id][key] = first_not_null(teams[team_id].get(key), candidate[key])


def upsert_player(players: dict[int, dict[str, Any]], player: dict[str, Any]) -> None:
    """Insert a player or enrich the first dimension row found for that ID."""
    player_id = to_int(player.get("player_id"))
    if player_id is None:
        return

    candidate = {
        "player_id": player_id,
        "player_name": clean_string(player.get("player_name")),
        "birth_date": normalize_date(player.get("birth_date")),
        "nationality": clean_string(player.get("nationality")),
        "position": clean_string(player.get("position")),
        "preferred_foot": clean_string(player.get("preferred_foot")),
        "team_id": to_int(player.get("team_id")),
    }
    if player_id not in players:
        players[player_id] = candidate
        return

    for key in (
        "player_name",
        "birth_date",
        "nationality",
        "position",
        "preferred_foot",
        "team_id",
    ):
        players[player_id][key] = first_not_null(players[player_id].get(key), candidate[key])


def extract_position(player: dict[str, Any]) -> str | None:
    """Map StatsBomb's detailed positions to the schema's four broad groups."""
    for position in player.get("positions") or []:
        name = clean_string(position.get("position"))
        if not name:
            continue
        if name == "Goalkeeper":
            return "Goalkeeper"
        if "Back" in name:
            return "Defender"
        if "Midfield" in name:
            return "Midfielder"
        if "Forward" in name or "Wing" in name or "Striker" in name:
            return "Forward"
    return None


def empty_metrics() -> dict[str, int]:
    """Create a fresh metric accumulator for one player-match row."""
    return {
        "goals": 0,
        "assists": 0,
        "shots": 0,
        "passes_completed": 0,
        "tackles": 0,
        "interceptions": 0,
        "yellow_cards": 0,
        "red_cards": 0,
    }


def calculate_event_data(
    events: list[dict[str, Any]],
) -> tuple[
    dict[int, dict[str, int]],
    dict[int, int],
    set[int],
    set[int],
    int,
    dict[int, dict[str, Any]],
]:
    """Aggregate event metrics and substitution information by player."""
    metrics: dict[int, dict[str, int]] = defaultdict(empty_metrics)
    substitution_out: dict[int, int] = {}
    substitution_in: set[int] = set()
    starters: set[int] = set()
    event_players: dict[int, dict[str, Any]] = {}
    periods: set[int] = set()

    for event in events:
        event_type = nested_name(event.get("type"))
        player = event.get("player") or {}
        team = event.get("team") or {}
        player_id = to_int(player.get("id"))
        team_id = to_int(team.get("id"))
        minute = to_int(event.get("minute")) or 0
        period = to_int(event.get("period"))
        if period is not None:
            periods.add(period)

        if player_id is not None:
            event_players[player_id] = {
                "player_id": player_id,
                "player_name": clean_string(player.get("name")),
                "team_id": team_id,
            }

        # Starting XI events identify the players who began the match.
        if event_type == "Starting XI":
            for item in (event.get("tactics") or {}).get("lineup") or []:
                starter = item.get("player") or {}
                starter_id = to_int(starter.get("id"))
                if starter_id is not None:
                    starters.add(starter_id)
                    event_players.setdefault(
                        starter_id,
                        {
                            "player_id": starter_id,
                            "player_name": clean_string(starter.get("name")),
                            "team_id": team_id,
                        },
                    )

        if player_id is None:
            continue

        if event_type == "Shot":
            metrics[player_id]["shots"] += 1
            if nested_name((event.get("shot") or {}).get("outcome")) == "Goal":
                metrics[player_id]["goals"] += 1

        elif event_type == "Pass":
            pass_data = event.get("pass") or {}
            # In StatsBomb, a pass without an outcome is a completed pass.
            if not pass_data.get("outcome"):
                metrics[player_id]["passes_completed"] += 1
            if pass_data.get("goal_assist") is True:
                metrics[player_id]["assists"] += 1

        elif event_type == "Duel":
            if nested_name((event.get("duel") or {}).get("type")) == "Tackle":
                metrics[player_id]["tackles"] += 1

        elif event_type == "Interception":
            metrics[player_id]["interceptions"] += 1

        elif event_type == "Substitution":
            replacement = (event.get("substitution") or {}).get("replacement") or {}
            replacement_id = to_int(replacement.get("id"))
            substitution_out[player_id] = minute
            if replacement_id is not None:
                substitution_in.add(replacement_id)
                event_players.setdefault(
                    replacement_id,
                    {
                        "player_id": replacement_id,
                        "player_name": clean_string(replacement.get("name")),
                        "team_id": team_id,
                    },
                )
                # Store the entry minute under a negative key to keep both
                # substitution directions in one compact return structure.
                substitution_out[-replacement_id] = minute

        card = None
        if event_type == "Foul Committed":
            card = nested_name((event.get("foul_committed") or {}).get("card"))
        elif event_type == "Bad Behaviour":
            card = nested_name((event.get("bad_behaviour") or {}).get("card"))

        if card in {"Yellow Card", "Second Yellow"}:
            metrics[player_id]["yellow_cards"] += 1
        if card in {"Red Card", "Second Yellow"}:
            metrics[player_id]["red_cards"] += 1

    # Ignore penalty shootouts for minutes played. Period 4 means extra time.
    match_length = 120 if 4 in periods else 90
    return metrics, substitution_out, substitution_in, starters, match_length, event_players


def estimate_minutes(
    player_id: int,
    has_events: bool,
    substitution_times: dict[int, int],
    substitution_in: set[int],
    starters: set[int],
    match_length: int,
) -> int:
    """Estimate minutes using starting-XI and substitution event data."""
    if not has_events:
        return 90

    entered_at = substitution_times.get(-player_id)
    left_at = substitution_times.get(player_id)

    if player_id in starters:
        return max(0, min(match_length, left_at if left_at is not None else match_length))
    if player_id in substitution_in and entered_at is not None:
        end = left_at if left_at is not None else match_length
        return max(0, min(match_length, end) - min(match_length, entered_at))

    # If events have no Starting XI data, an outgoing substitute is known to
    # have played from kickoff; other lineup players retain the 90-min estimate.
    if not starters:
        if left_at is not None:
            return max(0, min(match_length, left_at))
        return min(90, match_length)
    return 0


def calculate_rating(metrics: dict[str, int]) -> float:
    """Calculate and clamp the requested simple player rating."""
    rating = (
        6
        + metrics["goals"] * 0.8
        + metrics["assists"] * 0.5
        + metrics["shots"] * 0.05
        + metrics["passes_completed"] * 0.01
        + metrics["tackles"] * 0.05
        + metrics["interceptions"] * 0.05
        - metrics["yellow_cards"] * 0.3
        - metrics["red_cards"] * 1.0
    )
    return round(max(4.0, min(9.5, rating)), 2)


def clean_dataframe(
    rows: list[dict[str, Any]],
    columns: list[str],
    id_columns: list[str],
    deduplicate_by: list[str],
) -> pd.DataFrame:
    """Build a consistently ordered, deduplicated, NULL-clean dataframe."""
    dataframe = pd.DataFrame(rows, columns=columns)
    if dataframe.empty:
        return dataframe

    dataframe = dataframe.drop_duplicates(subset=deduplicate_by, keep="first")
    for column in dataframe.select_dtypes(include=["object", "str"]).columns:
        dataframe[column] = dataframe[column].replace(r"^\s*$", pd.NA, regex=True)
    for column in id_columns:
        dataframe[column] = pd.to_numeric(dataframe[column], errors="coerce").astype("Int64")
    return dataframe


def main() -> None:
    """Run the complete StatsBomb JSON-to-CSV transformation."""
    competitions_json = load_json(DATA_DIR / "competitions.json")
    if not isinstance(competitions_json, list):
        raise SystemExit(
            f"No se pudo cargar una lista válida desde {DATA_DIR / 'competitions.json'}"
        )

    selected_competitions = competitions_json[:MAX_COMPETITIONS]
    competitions: dict[int, dict[str, Any]] = {}
    teams: dict[int, dict[str, Any]] = {}
    matches: dict[int, dict[str, Any]] = {}
    players: dict[int, dict[str, Any]] = {}
    facts: list[dict[str, Any]] = []
    matches_processed = 0
    stop_processing = False

    for competition in selected_competitions:
        competition_id = to_int(competition.get("competition_id"))
        season_id = to_int(competition.get("season_id"))
        if competition_id is None or season_id is None:
            warn("Se omitió una competición con competition_id o season_id inválido.")
            continue

        # The schema stores one row per competition. Seasons belong to matches.
        competitions[competition_id] = {
            "competition_id": competition_id,
            "competition_name": clean_string(competition.get("competition_name")),
            "country_name": clean_string(competition.get("country_name")),
            "competition_type": (
                "International"
                if competition.get("competition_international") is True
                else "Domestic"
            ),
        }

        matches_path = DATA_DIR / "matches" / str(competition_id) / f"{season_id}.json"
        matches_json = load_json(matches_path)
        if not isinstance(matches_json, list):
            continue

        for match in matches_json:
            if MAX_MATCHES is not None and matches_processed >= MAX_MATCHES:
                stop_processing = True
                break

            match_id = to_int(match.get("match_id"))
            if match_id is None:
                warn(f"Partido sin match_id válido omitido en {matches_path}.")
                continue

            home_team = match.get("home_team") or {}
            away_team = match.get("away_team") or {}
            home_team_id = to_int(home_team.get("home_team_id"))
            away_team_id = to_int(away_team.get("away_team_id"))

            upsert_team(
                teams,
                {
                    "team_id": home_team_id,
                    "team_name": home_team.get("home_team_name"),
                    "country": nested_name(home_team.get("home_team_country")),
                },
            )
            upsert_team(
                teams,
                {
                    "team_id": away_team_id,
                    "team_name": away_team.get("away_team_name"),
                    "country": nested_name(away_team.get("away_team_country")),
                },
            )

            matches[match_id] = {
                "match_id": match_id,
                "competition_id": competition_id,
                "match_date": normalize_date(match.get("match_date")),
                "home_team_id": home_team_id,
                "away_team_id": away_team_id,
                "home_goals": to_int(match.get("home_score")) or 0,
                "away_goals": to_int(match.get("away_score")) or 0,
                "season": clean_string(competition.get("season_name")),
            }

            # A missing lineup does not stop later matches from being processed.
            lineups_path = DATA_DIR / "lineups" / f"{match_id}.json"
            lineups_json = load_json(lineups_path)
            if not isinstance(lineups_json, list):
                lineups_json = []

            lineup_players: dict[int, int | None] = {}
            for team_lineup in lineups_json:
                lineup_team_id = to_int(team_lineup.get("team_id"))
                upsert_team(
                    teams,
                    {
                        "team_id": lineup_team_id,
                        "team_name": team_lineup.get("team_name"),
                        "country": None,
                    },
                )

                for player in team_lineup.get("lineup") or []:
                    player_id = to_int(player.get("player_id"))
                    if player_id is None:
                        continue
                    lineup_players[player_id] = lineup_team_id
                    upsert_player(
                        players,
                        {
                            "player_id": player_id,
                            "player_name": player.get("player_name"),
                            "birth_date": player.get("birth_date"),
                            "nationality": nested_name(player.get("country")),
                            "position": extract_position(player),
                            "preferred_foot": None,
                            "team_id": lineup_team_id,
                        },
                    )

            events_json: list[dict[str, Any]] = []
            if USE_EVENTS:
                loaded_events = load_json(DATA_DIR / "events" / f"{match_id}.json")
                if isinstance(loaded_events, list):
                    events_json = loaded_events

            (
                event_metrics,
                substitution_times,
                substitution_in,
                starters,
                match_length,
                event_players,
            ) = calculate_event_data(events_json)

            # Include event-only players so useful statistics are not discarded
            # when a lineup file is incomplete.
            for player_id, event_player in event_players.items():
                lineup_players.setdefault(player_id, to_int(event_player.get("team_id")))
                upsert_player(players, event_player)

            for player_id, team_id in lineup_players.items():
                metrics = event_metrics.get(player_id, empty_metrics())
                fact = {
                    "player_id": player_id,
                    "match_id": match_id,
                    "minutes_played": estimate_minutes(
                        player_id,
                        bool(events_json),
                        substitution_times,
                        substitution_in,
                        starters,
                        match_length,
                    ),
                    **metrics,
                    "rating": calculate_rating(metrics),
                }
                facts.append(fact)

            matches_processed += 1

        if stop_processing:
            break

    competition_columns = [
        "competition_id",
        "competition_name",
        "country_name",
        "competition_type",
    ]
    team_columns = [
        "team_id",
        "team_name",
        "country",
        "city",
        "stadium",
        "founded_year",
    ]
    match_columns = [
        "match_id",
        "competition_id",
        "match_date",
        "home_team_id",
        "away_team_id",
        "home_goals",
        "away_goals",
        "season",
    ]
    player_columns = [
        "player_id",
        "player_name",
        "birth_date",
        "nationality",
        "position",
        "preferred_foot",
        "team_id",
    ]
    stats_columns = [
        "stat_id",
        "player_id",
        "match_id",
        "minutes_played",
        "goals",
        "assists",
        "shots",
        "passes_completed",
        "tackles",
        "interceptions",
        "yellow_cards",
        "red_cards",
        "rating",
    ]

    competition_df = clean_dataframe(
        list(competitions.values()),
        competition_columns,
        ["competition_id"],
        ["competition_id"],
    ).sort_values("competition_id")
    team_df = clean_dataframe(
        list(teams.values()), team_columns, ["team_id"], ["team_id"]
    ).sort_values("team_id")
    match_df = clean_dataframe(
        list(matches.values()),
        match_columns,
        ["match_id", "competition_id", "home_team_id", "away_team_id"],
        ["match_id"],
    ).sort_values("match_id")
    player_df = clean_dataframe(
        list(players.values()), player_columns, ["player_id", "team_id"], ["player_id"]
    ).sort_values("player_id")

    # Facts are unique by player and match. stat_id is generated only after
    # sorting, making it deterministic across repeated executions.
    player_match_stats_df = clean_dataframe(
        facts,
        [column for column in stats_columns if column != "stat_id"],
        ["player_id", "match_id"],
        ["player_id", "match_id"],
    ).sort_values(["match_id", "player_id"]).reset_index(drop=True)
    player_match_stats_df.insert(
        0, "stat_id", pd.Series(range(1, len(player_match_stats_df) + 1), dtype="Int64")
    )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    outputs = {
        "competition.csv": competition_df,
        "team.csv": team_df,
        "football_match.csv": match_df,
        "player.csv": player_df,
        "player_match_stats.csv": player_match_stats_df,
    }
    for filename, dataframe in outputs.items():
        dataframe.to_csv(OUTPUT_DIR / filename, index=False, encoding="utf-8")

    print("\nTransformación completada:")
    print(f"- Competiciones procesadas: {len(competition_df)}")
    print(f"- Partidos procesados: {len(match_df)}")
    print(f"- Equipos generados: {len(team_df)}")
    print(f"- Jugadores generados: {len(player_df)}")
    print(f"- Filas en player_match_stats: {len(player_match_stats_df)}")
    print(f"- CSV guardados en: {OUTPUT_DIR}")

    # Muestra una pequeña vista previa para revisar visualmente los datos
    # transformados antes de cargarlos en MySQL.
    if SHOW_PREVIEW:
        print(f"\nVista previa de los datos ({PREVIEW_ROWS} filas por tabla):")
        for filename, dataframe in outputs.items():
            print(f"\n--- {filename} ---")
            if dataframe.empty:
                print("[Sin filas]")
            else:
                print(dataframe.head(PREVIEW_ROWS).to_string(index=False))


if __name__ == "__main__":
    main()
