USE football_stats_db;

-- 02_data.sql
-- Este script se ejecuta después de importar los CSV.
-- La carga inicial se ha hecho desde CSV usando MySQL Workbench/DBeaver.
-- Aquí dejo documentado el orden de carga y aplico limpieza básica.

/*
Orden de importación CSV:
1. team.csv
2. competition.csv
3. football_match.csv
4. player.csv
5. player_match_stats.csv

Se cargan primero las dimensiones independientes y después la tabla de hechos,
para respetar las claves foráneas.
*/

START TRANSACTION;

-- Normalizo nacionalidades nulas para facilitar agrupaciones posteriores.
UPDATE player
SET nationality = 'Unknown'
WHERE nationality IS NULL OR TRIM(nationality) = '';

-- Normalizo posiciones nulas.
UPDATE player
SET position = 'Unknown'
WHERE position IS NULL OR TRIM(position) = '';

-- Normalizo pie preferido nulo.
UPDATE player
SET preferred_foot = 'Unknown'
WHERE preferred_foot IS NULL OR TRIM(preferred_foot) = '';

-- Elimino registros de hechos sin minutos ni rating porque no aportan análisis real.
DELETE FROM player_match_stats
WHERE minutes_played = 0
  AND rating IS NULL
  AND goals = 0
  AND assists = 0;

COMMIT;


-- Comprobación rápida de carga.
SELECT COUNT(*) AS total_teams FROM team;
SELECT COUNT(*) AS total_competitions FROM competition;
SELECT COUNT(*) AS total_matches FROM football_match;
SELECT COUNT(*) AS total_players FROM player;
SELECT COUNT(*) AS total_player_match_stats FROM player_match_stats;


-- Comprobación rápida de integridad referencial.
SELECT COUNT(*) AS orphan_player_stats
FROM player_match_stats f
LEFT JOIN player p ON f.player_id = p.player_id
WHERE p.player_id IS NULL;

SELECT COUNT(*) AS orphan_match_stats
FROM player_match_stats f
LEFT JOIN football_match m ON f.match_id = m.match_id
WHERE m.match_id IS NULL;