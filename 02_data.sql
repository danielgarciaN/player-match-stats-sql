USE football_stats_db;

-- 02_data.sql
-- Este script se ejecuta después de importar los CSV.
-- Revisa la calidad de los datos, corrige algunos valores nulos
-- y elimina registros que podrían afectar al análisis.

SET SQL_SAFE_UPDATES = 0;


/*
Orden de importación:
1. team.csv
2. competition.csv
3. football_match.csv
4. player.csv
5. player_match_stats.csv
*/


-- Registro de carga.
-- Guardo cuántas filas se han importado en cada tabla.

DROP TABLE IF EXISTS data_load_log;

CREATE TABLE IF NOT EXISTS data_load_log (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    rows_loaded INT NOT NULL,
    load_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO data_load_log (table_name, rows_loaded)
VALUES
    ('team', (SELECT COUNT(*) FROM team)),
    ('competition', (SELECT COUNT(*) FROM competition)),
    ('football_match', (SELECT COUNT(*) FROM football_match)),
    ('player', (SELECT COUNT(*) FROM player)),
    ('player_match_stats', (SELECT COUNT(*) FROM player_match_stats));

SELECT *
FROM data_load_log;


-- Comprobación de valores nulos.

SELECT COUNT(*) AS jugadores_sin_nacionalidad
FROM player
WHERE nationality IS NULL;

SELECT COUNT(*) AS equipos_sin_estadio
FROM team
WHERE stadium IS NULL;


-- Completo algunos valores nulos para facilitar agrupaciones posteriores.

UPDATE player
SET nationality = 'Unknown'
WHERE nationality IS NULL;

UPDATE team
SET stadium = 'Unknown'
WHERE stadium IS NULL;


-- Búsqueda de posibles duplicados.

SELECT
    player_id,
    match_id,
    COUNT(*) AS repeticiones
FROM player_match_stats
GROUP BY player_id, match_id
HAVING COUNT(*) > 1;


-- Segunda comprobación utilizando CTE.

WITH estadisticas_repetidas AS (
    SELECT
        stat_id,
        player_id,
        match_id,
        RANK() OVER (
            PARTITION BY player_id, match_id
            ORDER BY stat_id
        ) AS numero_repeticion
    FROM player_match_stats
)
SELECT *
FROM estadisticas_repetidas
WHERE numero_repeticion > 1;


-- Comprobación de fechas y valores fuera de rango.

SELECT *
FROM football_match
WHERE match_date > CURDATE()
   OR home_goals < 0
   OR away_goals < 0
   OR home_team_id = away_team_id;

SELECT *
FROM player_match_stats
WHERE minutes_played NOT BETWEEN 0 AND 120
   OR rating NOT BETWEEN 0 AND 10
   OR goals < 0
   OR assists < 0;


-- Competiciones con menos de 30 partidos.
-- Se eliminarán para evitar conclusiones basadas en muestras demasiado pequeñas.

SELECT
    c.competition_id,
    c.competition_name,
    COUNT(m.match_id) AS partidos
FROM competition c
LEFT JOIN football_match m
    ON m.competition_id = c.competition_id
GROUP BY c.competition_id, c.competition_name
HAVING COUNT(m.match_id) < 30
ORDER BY partidos;


START TRANSACTION;


-- Elimino estadísticas de partidos pertenecientes a competiciones pequeñas.

DELETE s
FROM player_match_stats s
INNER JOIN football_match m
    ON m.match_id = s.match_id
INNER JOIN (
    SELECT competition_id
    FROM football_match
    GROUP BY competition_id
    HAVING COUNT(*) < 30
) competiciones_pequenas
    ON competiciones_pequenas.competition_id = m.competition_id;


-- Elimino los partidos asociados.

DELETE m
FROM football_match m
INNER JOIN (
    SELECT resumen.competition_id
    FROM (
        SELECT competition_id
        FROM football_match
        GROUP BY competition_id
        HAVING COUNT(*) < 30
    ) resumen
) competiciones_pequenas
    ON competiciones_pequenas.competition_id = m.competition_id;


-- Elimino competiciones que ya no tienen partidos.

DELETE c
FROM competition c
LEFT JOIN football_match m
    ON m.competition_id = c.competition_id
WHERE m.match_id IS NULL;


-- Elimino jugadores sin estadísticas.

DELETE p
FROM player p
LEFT JOIN player_match_stats s
    ON s.player_id = p.player_id
WHERE s.stat_id IS NULL;


-- Elimino equipos que ya no aparecen ni en partidos ni en jugadores.

DELETE t
FROM team t
LEFT JOIN football_match local_match
    ON local_match.home_team_id = t.team_id
LEFT JOIN football_match away_match
    ON away_match.away_team_id = t.team_id
LEFT JOIN player p
    ON p.team_id = t.team_id
WHERE local_match.match_id IS NULL
  AND away_match.match_id IS NULL
  AND p.player_id IS NULL;

COMMIT;


-- Ejemplo de INSERT y ROLLBACK.
-- Lo hago sobre la tabla de log para no modificar el modelo principal.

START TRANSACTION;

INSERT INTO data_load_log (table_name, rows_loaded)
VALUES ('rollback_test', 0);

ROLLBACK;


-- Comprobación de integridad referencial.

SELECT COUNT(*) AS estadisticas_sin_jugador
FROM player_match_stats s
LEFT JOIN player p
    ON p.player_id = s.player_id
WHERE p.player_id IS NULL;

SELECT COUNT(*) AS estadisticas_sin_partido
FROM player_match_stats s
LEFT JOIN football_match m
    ON m.match_id = s.match_id
WHERE m.match_id IS NULL;

SELECT COUNT(*) AS partidos_sin_competicion
FROM football_match m
LEFT JOIN competition c
    ON c.competition_id = m.competition_id
WHERE c.competition_id IS NULL;

-- Caso de que un jugador esta en dos equipo (traspaso en el mercado de fichajes)
SELECT
    p.player_name,
    p.player_id,
    t.team_name
FROM player p
JOIN team t
    ON p.team_id = t.team_id
WHERE p.player_name IN (
    SELECT player_name
    FROM player
    GROUP BY player_name
    HAVING COUNT(DISTINCT team_id) > 1
)
ORDER BY p.player_name, p.player_id;

-- Resumen final de registros cargados.

SELECT COUNT(*) AS total_teams
FROM team;

SELECT COUNT(*) AS total_competitions
FROM competition;

SELECT COUNT(*) AS total_matches
FROM football_match;

SELECT COUNT(*) AS total_players
FROM player;

SELECT COUNT(*) AS total_player_match_stats
FROM player_match_stats;


SET SQL_SAFE_UPDATES = 1;