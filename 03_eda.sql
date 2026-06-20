USE football_stats_db;

-- 03_eda.sql
-- Consultas para obtener conclusiones claras sobre los datos de futbol.

-- Insight X. Jugadores por encima de la media de su posición.
-- Comparo cada jugador con la media de rating de su propia posición, no con la media global.
-- Así la comparación es más justa porque cada posición tiene funciones distintas.

SELECT
    p.player_name,
    p.position,
    COUNT(*) AS partidos,
    ROUND(AVG(s.rating), 2) AS rating_medio,
    ROUND((
        SELECT AVG(s2.rating)
        FROM player_match_stats s2
        JOIN player p2
            ON p2.player_id = s2.player_id
        WHERE p2.position = p.position
          AND s2.rating IS NOT NULL
    ), 2) AS media_posicion
FROM player_match_stats AS s
JOIN player AS p
    ON p.player_id = s.player_id
WHERE s.rating IS NOT NULL
GROUP BY
    p.player_id,
    p.player_name,
    p.position
HAVING COUNT(*) >= 20
   AND AVG(s.rating) > (
       SELECT AVG(s3.rating)
       FROM player_match_stats s3
       JOIN player p3
           ON p3.player_id = s3.player_id
       WHERE p3.position = p.position
         AND s3.rating IS NOT NULL
   )
ORDER BY
    p.position,
    rating_medio DESC;

-- Conclusión:
-- Esta consulta permite detectar jugadores que destacan dentro de su propio rol.
-- Comparar contra la media de la posición evita mezclar perfiles muy distintos,
-- como delanteros, defensas o porteros, y ayuda a identificar jugadores realmente
-- diferenciales dentro de su contexto.



-- Insight 2. Influencia de jugar como local en cada competicion.
SELECT
    c.competition_name,
    COUNT(*) AS partidos,
    SUM(CASE WHEN m.home_goals > m.away_goals THEN 1 ELSE 0 END) AS victorias_locales,
    SUM(CASE WHEN m.home_goals = m.away_goals THEN 1 ELSE 0 END) AS empates,
    SUM(CASE WHEN m.home_goals < m.away_goals THEN 1 ELSE 0 END) AS victorias_visitantes,
    ROUND(
        100.0 * SUM(CASE WHEN m.home_goals > m.away_goals THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS porcentaje_victorias_locales
FROM football_match AS m
JOIN competition AS c
    ON c.competition_id = m.competition_id
GROUP BY c.competition_id, c.competition_name
ORDER BY porcentaje_victorias_locales DESC;

-- Conclusión:
-- La mayoría de competiciones muestran más victorias locales que visitantes,
-- lo que sugiere una ventaja asociada a jugar en casa. Sin embargo, la magnitud
-- de esta ventaja varía entre competiciones.


-- Insight 3. Equipos mas eficientes de cara a gol
SELECT 
	t.team_name, 
	COUNT(DISTINCT f.match_id) AS partido,
	SUM(f.goals) AS goles,
	SUM(f.shots) AS tiros,
	ROUND(CAST(SUM(f.goals) AS DECIMAL(10,2)) / NULLIF(SUM(f.shots), 0),3) AS goles_por_tiro
FROM player_match_stats f
JOIN player p ON f.player_id = p.player_id 
JOIN team t ON p.team_id = t.team_id
GROUP BY t.team_id, t.team_name
HAVING SUM(f.shots) >= 100
ORDER BY goles_por_tiro DESC;

-- Conclusión:
-- Rusia presenta la mayor eficacia goleadora, aunque con una muestra más
-- reducida de partidos y tiros. Entre los equipos con más registros destacan Arsenal,
-- FC Barcelona, PSG, Inter de Milán y Francia, que mantienen una alta conversión de
-- ocasiones en gol, algo esperable en equipos acostumbrados a competir en la parte
-- alta de sus ligas. Por el contrario, equipos como Valladolid, Getafe o Huesca
-- muestran una menor eficacia ofensiva y necesitan más disparos para marcar.



-- Insight 4. Dependencia ofensiva de una estrella.
WITH contribuciones_por_jugador AS(
	SELECT
		p.player_id,
		p.player_name AS jugador,
		t.team_id,
		t.team_name AS equipo,
		SUM(f.goals) + SUM(f.assists) as total_contribuciones
	FROM player_match_stats f
	JOIN player p ON f.player_id = p.player_id
	JOIN team t ON p.team_id = t.team_id
	GROUP BY p.player_id, p.player_name, t.team_id, t.team_name
),
contribuciones_por_equipo AS (
	SELECT 
		team_id,
		equipo,
		SUM(total_contribuciones) AS total_contribuciones_equipo
	FROM contribuciones_por_jugador
	GROUP BY
		team_id,
		equipo
),
mejores_jugadores AS (
	SELECT 
		cj.equipo,
        cj.jugador,
        cj.total_contribuciones,
        ce.total_contribuciones_equipo,
        RANK() OVER (PARTITION BY cj.team_id ORDER BY cj.total_contribuciones DESC) AS ranking_jugador
    FROM contribuciones_por_jugador cj
    JOIN contribuciones_por_equipo ce ON cj.team_id = ce.team_id
)
SELECT 
	mj.jugador,
    mj.equipo,
    mj.total_contribuciones,
    mj.total_contribuciones_equipo,
    ROUND(mj.total_contribuciones / NULLIF(mj.total_contribuciones_equipo, 0) * 100,2) AS porcentaje_dependencia
FROM mejores_jugadores mj
WHERE ranking_jugador = 1 AND total_contribuciones_equipo >= 100
ORDER BY porcentaje_dependencia DESC;

-- Conclusión:
-- Algunos equipos concentran una gran parte de su producción ofensiva
-- en un único jugador, mientras que otros reparten las contribuciones
-- entre varios futbolistas. Una dependencia elevada puede convertirse
-- en un riesgo si ese jugador se lesiona o baja su rendimiento.


-- Insight 5. Jugadores infravalorados.
-- Uso la vista de rendimiento para buscar jugadores con buen rating,
-- pero con menos minutos que la media. Podrían ser perfiles a los que dar más oportunidades.

WITH medias_globales AS (
    SELECT
        AVG(rating_medio) AS media_rating_global,
        AVG(minutos_totales) AS media_minutos_global
    FROM vw_player_performance_summary
)
SELECT
    v.player_name AS jugador,
    v.partidos_jugados,
    v.minutos_totales,
    v.rating_medio,
    ROUND(m.media_rating_global, 2) AS media_rating_global,
    ROUND(m.media_minutos_global, 2) AS media_minutos_global
FROM vw_player_performance_summary v
CROSS JOIN medias_globales m
WHERE v.rating_medio > m.media_rating_global
  AND v.minutos_totales < m.media_minutos_global
  AND v.partidos_jugados >= 3
ORDER BY v.rating_medio DESC;

-- Conclusión:
-- Algunos jugadores mantienen un rendimiento por encima de la media a pesar de
-- haber disputado menos minutos que la mayoría. Esto sugiere que podrían estar
-- infrautilizados y merecer más oportunidades de juego.

-- Insight 6. Rendimiento por posición.
-- Comparo las estadísticas medias de cada posición para ver qué perfiles
-- destacan en cada aspecto del juego.

SELECT
	p.position,
    COUNT(DISTINCT p.player_id) as Jugadores,
    ROUND(AVG(f.rating),2) AS rating_medio,
    ROUND(AVG(f.goals),2) AS goles_medios,
    ROUND(AVG(f.assists),2) AS asistencias_medias,
    ROUND(AVG(f.shots),2) AS tiros_medios,
    ROUND(AVG(f.passes_completed),2) AS pases_medios,
    ROUND(AVG(f.tackles),2) AS tackles_medios,
    ROUND(AVG(f.interceptions),2) AS intercepciones_medias
FROM player_match_stats f
JOIN player p ON f.player_id = p.player_id
GROUP BY p.position
ORDER BY rating_medio DESC;

-- Conclusión:
-- Los resultados muestran diferencias claras entre posiciones.
-- Los delanteros destacan en métricas ofensivas, mientras que defensas
-- y centrocampistas concentran más acciones defensivas y de construcción de juego.

-- Insight 7. Mejores jugadores por posición.
-- Busco los jugadores con mejor rating medio dentro de cada posición.
WITH rating_jugadores AS (
    SELECT
        p.player_name,
        p.position,
        COUNT(DISTINCT f.match_id) AS partidos,
        ROUND(AVG(f.rating),2) AS rating_medio
    FROM player_match_stats f
    JOIN player p
        ON f.player_id = p.player_id
    GROUP BY
        p.player_id,
        p.player_name,
        p.position
),
ranking_posicion AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY position
            ORDER BY rating_medio DESC
        ) AS ranking_posicion
    FROM rating_jugadores
    WHERE partidos >= 50
)
SELECT
    position,
    player_name,
    partidos,
    rating_medio
FROM ranking_posicion
WHERE ranking_posicion <= 5
ORDER BY
    position,
    ranking_posicion;

-- Conclusión:
-- Al comparar jugadores dentro de su propia posición se observan perfiles
-- que destacan claramente sobre sus competidores directos. Este análisis
-- permite identificar referentes en cada rol sin sesgar la comparación
-- entre posiciones con funciones muy diferentes.



-- Insight 8. Jugadores con mejor promedio goleador.
-- Se utiliza el indice de jugador y partido creado en 01_schema.sql.
SELECT
    p.player_name,
    COUNT(*) AS partidos,
    SUM(s.goals) AS goles,
    ROUND(AVG(s.goals), 2) AS goles_por_partido
FROM player_match_stats AS s FORCE INDEX (idx_player_match_stats_player_match)
JOIN player AS p ON p.player_id = s.player_id
GROUP BY p.player_id, p.player_name
HAVING COUNT(*) >= 20
ORDER BY
    goles_por_partido DESC,
    goles DESC
LIMIT 20;

-- Conclusión:
-- El ranking muestra qué jugadores tienen mayor capacidad goleadora por partido,
-- pero se filtra por un mínimo de apariciones para que el resultado no dependa
-- de casos aislados con pocos registros.

-- Insight 9. Jugadores cuyo rating supera la media general.
-- Comparo el rating medio de cada jugador con la media global del dataset.

SELECT
    p.player_name,
    p.position,
    COUNT(*) AS partidos,
    ROUND(AVG(s.rating), 2) AS rating_medio
FROM player_match_stats AS s
JOIN player AS p ON p.player_id = s.player_id
WHERE s.rating IS NOT NULL
GROUP BY p.player_id, p.player_name, p.position
HAVING COUNT(*) >= 20
   AND AVG(s.rating) > (
       SELECT AVG(rating)
       FROM player_match_stats
       WHERE rating IS NOT NULL
   )
ORDER BY rating_medio DESC
LIMIT 20;

-- Conclusión:
-- Estos jugadores superan el rating medio global del dataset y además tienen
-- suficientes partidos registrados, por lo que pueden considerarse perfiles
-- de rendimiento alto y relativamente constante.

-- Insight 10. Evolución goleadora por temporada.
-- Uso funciones de fecha para analizar si el promedio de goles cambia con el tiempo.
-- Solo considero años con más de 100 partidos para evitar muestras pequeñas.

SELECT
    YEAR(m.match_date) AS anio,
    COUNT(*) AS partidos,
    SUM(m.home_goals + m.away_goals) AS goles_totales,
    ROUND(AVG(m.home_goals + m.away_goals), 2) AS goles_por_partido,
    MIN(m.match_date) AS primer_partido,
    MAX(m.match_date) AS ultimo_partido
FROM football_match AS m
GROUP BY YEAR(m.match_date)
HAVING COUNT(*) > 100
ORDER BY anio;

-- Conclusión:
-- El promedio de goles por partido se mantiene relativamente estable entre años,
-- aunque existen variaciones según las competiciones y temporadas incluidas en la muestra.
-- Este análisis ayuda a ver si el dataset refleja cambios generales en la producción ofensiva
-- a lo largo del tiempo.

-- Insight 11. Relación entre eficiencia ofensiva y rating medio.
-- Analizo si los jugadores clasificados como más eficientes
-- también obtienen mejores valoraciones medias.

SELECT
    efficiency_level,
    COUNT(*) AS jugadores,
    ROUND(AVG(rating_medio), 2) AS rating_medio_grupo,
    ROUND(AVG(contribuciones_ofensivas), 2) AS contribuciones_medias,
    ROUND(AVG(minutos_totales), 2) AS minutos_medios
FROM vw_player_performance_summary
WHERE partidos_jugados >= 20
GROUP BY efficiency_level
ORDER BY rating_medio_grupo DESC;

-- Conclusión:
-- Los jugadores clasificados con una eficiencia ofensiva alta suelen presentar
-- mejores ratings medios que el resto. Esto sugiere que la capacidad de generar
-- goles y asistencias por minuto jugado está relacionada con una valoración
-- global más alta de su rendimiento.
