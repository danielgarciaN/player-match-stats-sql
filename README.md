# Proyecto de análisis de fútbol con SQL

## Descripción

Este proyecto utiliza datos abiertos de StatsBomb para analizar partidos, competiciones, equipos y jugadores mediante SQL. Los datos originales se encuentran en formato JSON y han sido transformados a CSV para facilitar su carga en una base de datos relacional.

La tabla principal del modelo es `player_match_stats`, donde cada fila representa el rendimiento de un jugador en un partido concreto. Las tablas `player`, `team`, `competition` y `football_match` aportan el contexto necesario para interpretar esas estadísticas.

El objetivo es aplicar técnicas de modelado relacional, limpieza de datos y análisis exploratorio para extraer conclusiones relevantes a partir de datos reales de fútbol.

![Modelo relacional](model.jpg)

---

## Video de la presentacion

[Ver video de la presentacion](https://www.loom.com/share/2bcabd1eb1344d5cb5fde0393808aa6b)

---

## Modelo de datos

El proyecto sigue un modelo dimensional sencillo.

### Tabla de hechos

- `player_match_stats`

### Dimensiones

- `player`
- `team`
- `competition`
- `football_match`

La granularidad de la tabla principal es una fila por jugador y partido.

---

## Archivos principales

- `01_schema.sql`: creación de la base de datos, tablas, claves primarias, claves foráneas, restricciones, índice, función y vistas.
- `02_data.sql`: validación y limpieza de los datos cargados.
- `03_eda.sql`: consultas analíticas e insights obtenidos.
- `data_clean/`: archivos CSV preparados para la importación.
- `transform_statsbomb_to_csv.py`: script utilizado para transformar los JSON originales de StatsBomb a CSV.
- `model.jpg`: diagrama entidad-relación del modelo.

---

## Ejecución

El proyecto está preparado para MySQL 8.0 o superior.

### 1. Crear la estructura

Ejecutar:

```sql
01_schema.sql
```

### 2. Importar los CSV

Importar los archivos en el siguiente orden:

1. `team.csv`
2. `competition.csv`
3. `football_match.csv`
4. `player.csv`
5. `player_match_stats.csv`

### 3. Ejecutar la limpieza

```sql
02_data.sql
```

### 4. Ejecutar el análisis

```sql
03_eda.sql
```

---

## Preparación de los datos

El conjunto original contiene 24 competiciones. Sin embargo, algunas de ellas disponen de muy pocos partidos registrados, lo que dificulta la obtención de conclusiones fiables.

Por este motivo, en `02_data.sql` se identifican las competiciones con menos de 30 partidos y se eliminan junto con sus estadísticas asociadas. También se eliminan jugadores sin registros estadísticos y equipos que quedan sin relación con el resto de tablas.

Además, el script realiza comprobaciones sobre:

- Valores nulos.
- Registros duplicados.
- Fechas incorrectas.
- Valores fuera de rango.
- Integridad referencial.
- Registros huérfanos.

Toda la limpieza se realiza mediante transacciones para garantizar la consistencia de los datos.

### Resultado final después de la limpieza

| Tabla | Registros |
|---------|---------:|
| `team` | 344 |
| `competition` | 17 |
| `football_match` | 3897 |
| `player` | 9508 |
| `player_match_stats` | 143917 |

La reducción de registros se debe principalmente a la eliminación de competiciones con muy pocos partidos, ya que una muestra tan pequeña podría producir conclusiones poco representativas.

---

## Análisis exploratorio

Las consultas de `03_eda.sql` utilizan una muestra final de:

- 3.897 partidos
- 9.508 jugadores
- 143.917 registros individuales de rendimiento

A partir de estos datos se responden las siguientes preguntas:

1. ¿Qué competiciones tienen un mayor promedio de goles?
2. ¿En qué competiciones influye más jugar como local?
3. ¿Qué equipos son más eficientes de cara a gol?
4. ¿Qué equipos dependen más de un único jugador para generar goles y asistencias?
5. ¿Qué jugadores podrían estar infravalorados por jugar menos minutos de los esperados?
6. ¿Cómo cambia el rendimiento según la posición del jugador?
7. ¿Quiénes son los mejores jugadores de cada posición según su rating?
8. ¿Qué jugadores tienen el mejor promedio goleador?
9. ¿Qué jugadores superan el rating medio global del dataset?
10. ¿Cómo ha evolucionado el promedio de goles por año?
11. ¿Qué relación existe entre la eficiencia ofensiva y el rating medio de los jugadores?

Las consultas combinan agregaciones, filtros, uniones, subconsultas, funciones ventana y vistas de negocio para obtener conclusiones de forma sencilla y reproducible.

---

## Técnicas SQL utilizadas

Durante el desarrollo del proyecto se han utilizado las siguientes técnicas:

- `CREATE TABLE`
- `PRIMARY KEY`
- `FOREIGN KEY`
- `CHECK`
- `UNIQUE`
- `INSERT`
- `UPDATE`
- `DELETE`
- `CAST`
- `COUNT`
- `SUM`
- `AVG`
- `CASE`
- `INNER JOIN`
- `LEFT JOIN`
- Subqueries
- CTE (`WITH`)
- CTE encadenadas
- Funciones ventana (`RANK() OVER(PARTITION BY ...)`)
- Funciones de fecha (`YEAR`, `CURDATE`)
- Transacciones (`START TRANSACTION`, `COMMIT`, `ROLLBACK`)
- Índices
- Funciones SQL personalizadas
- Vistas de negocio

---

## Elementos destacados del modelo

### Índice

Se ha creado el índice:

```sql
idx_player_match_stats_player_match
```

Su objetivo es acelerar consultas frecuentes sobre el rendimiento de jugadores por partido.

### Función SQL

Se ha implementado la función:

```sql
fn_efficiency_level()
```

Esta función clasifica a los jugadores según sus contribuciones ofensivas por 90 minutos en categorías de eficiencia.

### Vistas

Se han creado dos vistas de negocio:

#### `vw_player_performance_summary`

Resume el rendimiento acumulado de cada jugador.

#### `vw_team_performance_summary`

Resume el rendimiento agregado de cada equipo.

Estas vistas simplifican varias de las consultas utilizadas en el análisis exploratorio.

---

## Objetivo del proyecto

El objetivo principal es aplicar los conceptos aprendidos durante el módulo de SQL a un caso real basado en datos deportivos.

Para ello se han desarrollado las distintas fases habituales de un proyecto de datos:

1. Obtención de los datos.
2. Transformación y carga.
3. Diseño del modelo relacional.
4. Validación y limpieza.
5. Análisis exploratorio.
6. Obtención de conclusiones mediante SQL.

---

## Limitaciones

Los datos abiertos de StatsBomb no contienen todos los partidos disputados en cada competición o temporada.

Por tanto, los resultados obtenidos describen únicamente la muestra disponible y no deben interpretarse como clasificaciones oficiales completas.

Además, algunas competiciones, equipos y jugadores cuentan con más registros que otros, por lo que ciertas conclusiones pueden verse afectadas por diferencias en el tamaño de la muestra.
