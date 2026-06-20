DROP DATABASE IF EXISTS football_stats_db;

CREATE DATABASE IF NOT EXISTS football_stats_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE football_stats_db;

/*
TABLA: team
Guarda la información básica de los equipos.
La separo en una dimensión para no repetir el nombre, país o estadio
cada vez que aparezca un equipo en un partido o en un jugador.
*/

CREATE TABLE IF NOT EXISTS team (
    team_id INT NOT NULL,
    team_name VARCHAR(150) NOT NULL,
    country VARCHAR(100) NOT NULL,
    stadium VARCHAR(150),

    CONSTRAINT pk_team PRIMARY KEY (team_id),

    -- Evita duplicar el mismo equipo dentro del mismo país.
    CONSTRAINT uq_team_name_country UNIQUE (team_name, country)
);


/*
TABLA: competition
Contiene las competiciones en las que se juegan los partidos.
Es una dimensión porque describe el contexto del partido.
*/

CREATE TABLE IF NOT EXISTS competition (
    competition_id INT NOT NULL,
    competition_name VARCHAR(150) NOT NULL,
    country_name VARCHAR(100) NOT NULL,
    competition_type VARCHAR(50) NOT NULL,

    CONSTRAINT pk_competition PRIMARY KEY (competition_id),

    -- Una competición no debería repetirse con el mismo nombre, país y tipo.
    CONSTRAINT uq_competition UNIQUE (
        competition_name,
        country_name,
        competition_type
    )
);


/*
TABLA: football_match
Guarda la información de cada partido.
Aunque un partido es un evento, aquí funciona como dimensión
porque sirve para contextualizar las estadísticas de los jugadores.
*/

CREATE TABLE IF NOT EXISTS football_match (
    match_id INT NOT NULL,
    competition_id INT NOT NULL,
    match_date DATE NOT NULL,
    home_team_id INT NOT NULL,
    away_team_id INT NOT NULL,
    home_goals INT NOT NULL DEFAULT 0,
    away_goals INT NOT NULL DEFAULT 0,
    season VARCHAR(20) NOT NULL,

    CONSTRAINT pk_football_match PRIMARY KEY (match_id),

    CONSTRAINT chk_match_home_goals CHECK (home_goals >= 0),
    CONSTRAINT chk_match_away_goals CHECK (away_goals >= 0),

    CONSTRAINT fk_match_competition
        FOREIGN KEY (competition_id)
        REFERENCES competition(competition_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_match_home_team
        FOREIGN KEY (home_team_id)
        REFERENCES team(team_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_match_away_team
        FOREIGN KEY (away_team_id)
        REFERENCES team(team_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
        
	-- La regla home_team_id <> away_team_id se validará en el EDA.
    -- MySQL no permite bien este CHECK cuando las columnas también participan en FKs.
    
);

/*
TABLA: Player
Contiene la información descriptiva de cada jugador.
Incluyo team_id para relacionar cada jugador con su equipo.
*/

CREATE TABLE IF NOT EXISTS player (
    player_id INT NOT NULL,
    player_name VARCHAR(150) NOT NULL,
    nationality VARCHAR(100),
    position VARCHAR(50),
    team_id INT,

    CONSTRAINT pk_player PRIMARY KEY (player_id),

    -- Limito las posiciones a grupos generales para facilitar el análisis.
    CONSTRAINT chk_player_position
        CHECK (
            position IS NULL
            OR position IN ('Goalkeeper', 'Defender', 'Midfielder', 'Forward')
        ),

    -- Cada jugador puede estar asociado a un equipo.
    CONSTRAINT fk_player_team
        FOREIGN KEY (team_id)
        REFERENCES team(team_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL
);


/*
TABLA DE HECHOS: player_match_stats
Esta es la tabla principal del modelo.
Granularidad: una fila representa el rendimiento de un jugador
en un partido concreto.
 
Las métricas como goles, asistencias, minutos, pases o rating
van aquí porque cambian en cada partido.
*/

CREATE TABLE IF NOT EXISTS player_match_stats (
    stat_id INT NOT NULL AUTO_INCREMENT,
    player_id INT NOT NULL,
    match_id INT NOT NULL,

    minutes_played INT NOT NULL DEFAULT 0,
    goals INT NOT NULL DEFAULT 0,
    assists INT NOT NULL DEFAULT 0,
    shots INT NOT NULL DEFAULT 0,
    passes_completed INT NOT NULL DEFAULT 0,
    tackles INT NOT NULL DEFAULT 0,
    interceptions INT NOT NULL DEFAULT 0,
    yellow_cards INT NOT NULL DEFAULT 0,
    red_cards INT NOT NULL DEFAULT 0,
    rating DECIMAL(4,2),

    CONSTRAINT pk_player_match_stats PRIMARY KEY (stat_id),

    CONSTRAINT uq_player_match_stats_player_match UNIQUE (player_id, match_id),

    CONSTRAINT chk_player_match_stats_minutes_played
        CHECK (minutes_played BETWEEN 0 AND 120),

    CONSTRAINT chk_player_match_stats_goals CHECK (goals >= 0),
    CONSTRAINT chk_player_match_stats_assists CHECK (assists >= 0),
    CONSTRAINT chk_player_match_stats_shots CHECK (shots >= 0),
    CONSTRAINT chk_player_match_stats_passes_completed CHECK (passes_completed >= 0),
    CONSTRAINT chk_player_match_stats_tackles CHECK (tackles >= 0),
    CONSTRAINT chk_player_match_stats_interceptions CHECK (interceptions >= 0),

    CONSTRAINT chk_player_match_stats_yellow_cards
        CHECK (yellow_cards BETWEEN 0 AND 2),

    CONSTRAINT chk_player_match_stats_red_cards
        CHECK (red_cards BETWEEN 0 AND 1),

    CONSTRAINT chk_player_match_stats_rating
        CHECK (rating IS NULL OR rating BETWEEN 0 AND 10),

    CONSTRAINT fk_player_match_stats_player
        FOREIGN KEY (player_id)
        REFERENCES player(player_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_player_match_stats_match
        FOREIGN KEY (match_id)
        REFERENCES football_match(match_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

/*
ÍNDICES
Los índices ayudan a acelerar consultas que se repetirán mucho
en el análisis exploratorio.
*/

-- Este índice está formado por player_id y match_id.
-- Se utilizará en consultas que buscan las estadísticas de un jugador
-- en uno o varios partidos concretos, evitando recorrer toda la tabla
-- player_match_stats. Esto es especialmente útil porque es la tabla con
-- más registros del modelo y muchas consultas filtran o agrupan por jugador.

CREATE INDEX idx_player_match_stats_player_match
ON player_match_stats(player_id, match_id);


    
/*
FUNCION: fn_efficiency_level
Clasifica el impacto ofensivo de un jugador usando contribuciones por 90 minutos.
Así no depende tanto del número total de partidos registrados.
*/

DROP FUNCTION IF EXISTS fn_efficiency_level;

DELIMITER $$

CREATE FUNCTION fn_efficiency_level(contributions_per_90 DECIMAL(10,2))
RETURNS VARCHAR(20)
DETERMINISTIC
NO SQL
BEGIN
    RETURN CASE
        WHEN contributions_per_90 IS NULL THEN 'Unknown'
        WHEN contributions_per_90 >= 0.80 THEN 'High efficiency'
        WHEN contributions_per_90 >= 0.40 THEN 'Medium efficiency'
        ELSE 'Low efficiency'
    END;
END$$

DELIMITER ;

/*
VISTA: vw_player_performance_summary
Resume el rendimiento acumulado por jugador.
Me servirá para rankings y análisis generales de rendimiento.
*/

CREATE OR REPLACE VIEW vw_player_performance_summary AS
SELECT
    p.player_id,
    p.player_name,
    COUNT(DISTINCT f.match_id) AS partidos_jugados,
    SUM(f.minutes_played) AS minutos_totales,
    SUM(f.goals) AS goles_totales,
    SUM(f.assists) AS asistencias_totales,
    SUM(f.goals + f.assists) AS contribuciones_ofensivas,
    fn_efficiency_level(ROUND(SUM(f.goals + f.assists) / NULLIF(SUM(f.minutes_played), 0) * 90,2)) AS efficiency_level,
    ROUND(AVG(f.rating), 2) AS rating_medio
FROM player p
INNER JOIN player_match_stats f
    ON p.player_id = f.player_id
GROUP BY
    p.player_id,
    p.player_name;


/*
VISTA: vw_team_performance_summary
Resume el rendimiento acumulado por equipo.
La uso para comparar equipos sin repetir agregaciones en cada consulta.
*/

CREATE OR REPLACE VIEW vw_team_performance_summary AS
SELECT
    t.team_id,
    t.team_name,
    COUNT(DISTINCT p.player_id) AS jugadores,
    COUNT(DISTINCT f.match_id) AS partidos_con_registro,
    SUM(f.goals) AS goles_totales,
    SUM(f.assists) AS asistencias_totales,
    SUM(f.goals + f.assists) AS contribuciones_ofensivas,
    ROUND(AVG(f.rating), 2) AS rating_medio_equipo
FROM team t
LEFT JOIN player p
    ON t.team_id = p.team_id
LEFT JOIN player_match_stats f
    ON p.player_id = f.player_id
GROUP BY
    t.team_id,
    t.team_name;

/*
Fin del schema.
El orden de creación es importante: primero las dimensiones,
luego la tabla de hechos, y al final índices, función y vistas.
*/

SHOW TABLES;
