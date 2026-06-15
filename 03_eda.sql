USE football_stats_db;

-- 03_eda.sql
-- Analisis exploratorio de los partidos y del rendimiento de los jugadores.
-- Este script solo contiene consultas: no limpia datos ni crea vistas o indices.


-- Insight 1. Volumen y nivel goleador por competicion y temporada.
-- Permite comparar el tamano de cada muestra y su promedio de goles por partido.
SELECT
    c.competition_name,
    c.country_name,
    m.season,
    COUNT(*) AS partidos,
    SUM(m.home_goals + m.away_goals) AS goles_totales,
    ROUND(AVG(CAST(m.home_goals + m.away_goals AS DECIMAL(10, 2))), 2) AS goles_por_partido,
    YEAR(MIN(m.match_date)) AS primer_ano,
    YEAR(MAX(m.match_date)) AS ultimo_ano
FROM football_match AS m
INNER JOIN competition AS c
    ON c.competition_id = m.competition_id
GROUP BY
    c.competition_id,
    c.competition_name,
    c.country_name,
    m.season
ORDER BY goles_por_partido DESC, partidos DESC;


-- Insight 2. Ventaja de jugar como local por competicion.
-- Mide victorias locales, empates y visitantes, ademas de la diferencia media de goles.
SELECT
    c.competition_name,
    COUNT(*) AS partidos,
    SUM(CASE WHEN m.home_goals > m.away_goals THEN 1 ELSE 0 END) AS victorias_locales,
    SUM(CASE WHEN m.home_goals = m.away_goals THEN 1 ELSE 0 END) AS empates,
    SUM(CASE WHEN m.home_goals < m.away_goals THEN 1 ELSE 0 END) AS victorias_visitantes,
    ROUND(
        100.0 * SUM(CASE WHEN m.home_goals > m.away_goals THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS porcentaje_victorias_locales,
    ROUND(AVG(CAST(m.home_goals - m.away_goals AS DECIMAL(10, 2))), 2) AS diferencia_media_local
FROM football_match AS m
INNER JOIN competition AS c
    ON c.competition_id = m.competition_id
GROUP BY c.competition_id, c.competition_name
ORDER BY porcentaje_victorias_locales DESC;


-- Insight 3. Clasificacion calculada por competicion y temporada.
-- Las CTE encadenadas convierten cada partido en dos registros y calculan puntos y posicion.
WITH match_sides AS (
    SELECT
        m.competition_id,
        m.season,
        m.home_team_id AS team_id,
        m.home_goals AS goals_for,
        m.away_goals AS goals_against,
        CASE
            WHEN m.home_goals > m.away_goals THEN 3
            WHEN m.home_goals = m.away_goals THEN 1
            ELSE 0
        END AS points
    FROM football_match AS m

    UNION ALL

    SELECT
        m.competition_id,
        m.season,
        m.away_team_id AS team_id,
        m.away_goals AS goals_for,
        m.home_goals AS goals_against,
        CASE
            WHEN m.away_goals > m.home_goals THEN 3
            WHEN m.away_goals = m.home_goals THEN 1
            ELSE 0
        END AS points
    FROM football_match AS m
),
team_totals AS (
    SELECT
        competition_id,
        season,
        team_id,
        COUNT(*) AS partidos,
        SUM(goals_for) AS goles_favor,
        SUM(goals_against) AS goles_contra,
        SUM(goals_for - goals_against) AS diferencia_goles,
        SUM(points) AS puntos
    FROM match_sides
    GROUP BY competition_id, season, team_id
),
ranked_teams AS (
    SELECT
        tt.*,
        DENSE_RANK() OVER (
            PARTITION BY tt.competition_id, tt.season
            ORDER BY tt.puntos DESC, tt.diferencia_goles DESC, tt.goles_favor DESC
        ) AS posicion
    FROM team_totals AS tt
)
SELECT
    c.competition_name,
    r.season,
    r.posicion,
    t.team_name,
    r.partidos,
    r.goles_favor,
    r.goles_contra,
    r.diferencia_goles,
    r.puntos
FROM ranked_teams AS r
INNER JOIN competition AS c
    ON c.competition_id = r.competition_id
INNER JOIN team AS t
    ON t.team_id = r.team_id
WHERE r.posicion <= 5
ORDER BY c.competition_name, r.season, r.posicion;


-- Insight 4. Jugadores con mayor produccion ofensiva acumulada.
-- Reutiliza la vista de negocio creada en 01_schema.sql.
SELECT
    v.player_name,
    v.partidos_jugados,
    v.minutos_totales,
    v.goles_totales,
    v.asistencias_totales,
    v.contribuciones_ofensivas,
    ROUND(
        90.0 * v.contribuciones_ofensivas / NULLIF(v.minutos_totales, 0),
        2
    ) AS contribuciones_por_90,
    v.rating_medio
FROM vw_player_performance_summary AS v
WHERE v.minutos_totales >= 900
ORDER BY contribuciones_por_90 DESC, v.contribuciones_ofensivas DESC
LIMIT 20;


-- Insight 5. Jugadores que superan el rating medio global.
-- La subquery establece una referencia comun antes de ordenar los mejores rendimientos.
SELECT
    v.player_name,
    v.partidos_jugados,
    v.rating_medio,
    ROUND(
        v.rating_medio - (
            SELECT AVG(s.rating)
            FROM player_match_stats AS s
            WHERE s.rating IS NOT NULL
        ),
        2
    ) AS diferencia_sobre_media
FROM vw_player_performance_summary AS v
WHERE v.partidos_jugados >= 10
  AND v.rating_medio > (
      SELECT AVG(s.rating)
      FROM player_match_stats AS s
      WHERE s.rating IS NOT NULL
  )
ORDER BY diferencia_sobre_media DESC, v.partidos_jugados DESC
LIMIT 25;


-- Insight 6. Lideres de rendimiento dentro de cada posicion.
-- Se fuerza el indice de jugador y partido porque esta consulta agrega la tabla de hechos por jugador.
WITH player_position_summary AS (
    SELECT
        p.player_id,
        p.player_name,
        p.position,
        COUNT(*) AS partidos,
        SUM(s.minutes_played) AS minutos,
        ROUND(AVG(s.rating), 2) AS rating_medio,
        SUM(s.goals + s.assists) AS contribuciones
    FROM player_match_stats AS s FORCE INDEX (idx_player_match_stats_player_match)
    INNER JOIN player AS p
        ON p.player_id = s.player_id
    WHERE s.rating IS NOT NULL
      AND p.position IS NOT NULL
    GROUP BY p.player_id, p.player_name, p.position
    HAVING COUNT(*) >= 10
),
position_ranking AS (
    SELECT
        pps.*,
        DENSE_RANK() OVER (
            PARTITION BY pps.position
            ORDER BY pps.rating_medio DESC, pps.contribuciones DESC
        ) AS ranking_posicion
    FROM player_position_summary AS pps
)
SELECT
    position,
    ranking_posicion,
    player_name,
    partidos,
    minutos,
    rating_medio,
    contribuciones
FROM position_ranking
WHERE ranking_posicion <= 5
ORDER BY position, ranking_posicion, player_name;


-- Insight 7. Perfil ofensivo y defensivo de cada posicion.
-- Ayuda a comprobar que acciones caracterizan a defensas, centrocampistas y delanteros.
SELECT
    p.position,
    COUNT(*) AS actuaciones,
    ROUND(AVG(s.minutes_played), 2) AS minutos_medios,
    ROUND(AVG(s.shots), 2) AS tiros_medios,
    ROUND(AVG(s.passes_completed), 2) AS pases_medios,
    ROUND(AVG(s.tackles), 2) AS entradas_medias,
    ROUND(AVG(s.interceptions), 2) AS intercepciones_medias,
    ROUND(AVG(s.rating), 2) AS rating_medio
FROM player_match_stats AS s
INNER JOIN player AS p
    ON p.player_id = s.player_id
WHERE p.position IS NOT NULL
GROUP BY p.position
ORDER BY rating_medio DESC;


-- Insight 8. Disciplina por competicion y posicion.
-- Relaciona cuatro tablas para localizar los contextos con mas tarjetas por actuacion.
SELECT
    c.competition_name,
    p.position,
    COUNT(*) AS actuaciones,
    SUM(s.yellow_cards) AS amarillas,
    SUM(s.red_cards) AS rojas,
    ROUND(
        100.0 * SUM(s.yellow_cards + s.red_cards) / COUNT(*),
        2
    ) AS tarjetas_por_100_actuaciones
FROM player_match_stats AS s
INNER JOIN player AS p
    ON p.player_id = s.player_id
INNER JOIN football_match AS m
    ON m.match_id = s.match_id
INNER JOIN competition AS c
    ON c.competition_id = m.competition_id
WHERE p.position IS NOT NULL
GROUP BY c.competition_id, c.competition_name, p.position
HAVING COUNT(*) >= 20
ORDER BY tarjetas_por_100_actuaciones DESC, actuaciones DESC;


-- Insight 9. Representacion y uso de jugadores por nacionalidad.
-- El LEFT JOIN conserva tambien a los jugadores que no tienen estadisticas registradas.
SELECT
    COALESCE(p.nationality, 'Sin nacionalidad informada') AS nacionalidad,
    COUNT(DISTINCT p.player_id) AS jugadores,
    COUNT(s.stat_id) AS actuaciones_registradas,
    COALESCE(SUM(s.minutes_played), 0) AS minutos_totales,
    ROUND(AVG(s.rating), 2) AS rating_medio
FROM player AS p
LEFT JOIN player_match_stats AS s
    ON s.player_id = p.player_id
GROUP BY COALESCE(p.nationality, 'Sin nacionalidad informada')
HAVING COUNT(DISTINCT p.player_id) >= 10
ORDER BY minutos_totales DESC, jugadores DESC;


-- Insight 10. Evolucion mensual del promedio goleador.
-- La media movil suaviza meses aislados y permite observar tendencias dentro de cada competicion.
WITH monthly_goals AS (
    SELECT
        m.competition_id,
        DATE_FORMAT(m.match_date, '%Y-%m-01') AS month_start,
        COUNT(*) AS partidos,
        SUM(m.home_goals + m.away_goals) AS goles,
        AVG(CAST(m.home_goals + m.away_goals AS DECIMAL(10, 2))) AS goles_por_partido
    FROM football_match AS m
    GROUP BY
        m.competition_id,
        DATE_FORMAT(m.match_date, '%Y-%m-01')
),
monthly_trend AS (
    SELECT
        mg.*,
        AVG(mg.goles_por_partido) OVER (
            PARTITION BY mg.competition_id
            ORDER BY mg.month_start
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS media_movil_tres_meses
    FROM monthly_goals AS mg
)
SELECT
    c.competition_name,
    CAST(mt.month_start AS DATE) AS mes,
    mt.partidos,
    mt.goles,
    ROUND(mt.goles_por_partido, 2) AS goles_por_partido,
    ROUND(mt.media_movil_tres_meses, 2) AS media_movil_tres_meses
FROM monthly_trend AS mt
INNER JOIN competition AS c
    ON c.competition_id = mt.competition_id
ORDER BY c.competition_name, mes;
