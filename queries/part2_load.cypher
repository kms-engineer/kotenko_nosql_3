// ----------------------------------------------------------------------------
// 1. ОБМЕЖЕННЯ УНІКАЛЬНОСТІ (= індекси)
// ----------------------------------------------------------------------------
// Constraint у Neo4j автоматично створює backing-індекс. Тобто одночасно:
//   (а) гарантуємо унікальність ключа -> MERGE не зробить дублікатів;
//   (б) отримуємо індекс, який різко прискорює MATCH (u {userId:...}) при
//       завантаженні мільйона ребер RATED.
// Створюємо ДО завантаження ребер — щоб пошук вузлів був миттєвим.
CREATE CONSTRAINT user_id   IF NOT EXISTS FOR (u:User)  REQUIRE u.userId  IS UNIQUE;
CREATE CONSTRAINT movie_id  IF NOT EXISTS FOR (m:Movie) REQUIRE m.movieId IS UNIQUE;
CREATE CONSTRAINT genre_name IF NOT EXISTS FOR (g:Genre) REQUIRE g.name   IS UNIQUE;


// ----------------------------------------------------------------------------
// 2. ВУЗЛИ: КОРИСТУВАЧІ
// ----------------------------------------------------------------------------
// MERGE (а не CREATE) — ідемпотентність: повторний запуск не наплодить копій.
// Числові поля приводимо toInteger, бо LOAD CSV читає все як рядки.
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
MERGE (u:User {userId: toInteger(row.userId)})
SET u.gender     = row.gender,
    u.age        = toInteger(row.age),         // код вікової групи (1,18,25,...)
    u.occupation = toInteger(row.occupation);  // код професії (0..20)


// ----------------------------------------------------------------------------
// 3. ВУЗЛИ: ФІЛЬМИ + ЖАНРИ (+ ребра HAS_GENRE)
// ----------------------------------------------------------------------------
// year витягуємо з назви: усі назви закінчуються на " (РРРР)", тому
// 4 символи перед закриваючою дужкою: substring(title, size-5, 4).
// Жанри розбиваємо split(genres,'|') і нормалізуємо в окремі вузли Genre,
// з'єднуючи (Movie)-[:HAS_GENRE]->(Genre). MERGE на Genre дедуплікує 18 жанрів.
LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
MERGE (m:Movie {movieId: toInteger(row.movieId)})
SET m.title = row.title,
    m.year  = toInteger(substring(row.title, size(row.title) - 5, 4))
WITH m, row
UNWIND split(row.genres, '|') AS genreName
MERGE (g:Genre {name: genreName})
MERGE (m)-[:HAS_GENRE]->(g);


// ----------------------------------------------------------------------------
// 4. РЕБРА: ОЦІНКИ (RATED) — БАТЧАМИ через apoc.periodic.iterate
// ----------------------------------------------------------------------------
// 1 000 209 ребер не можна вставити однією транзакцією — впаде по пам'яті/таймауту.
// apoc.periodic.iterate розбиває роботу на батчі по 10 000:
//   - 1-й аргумент (driver): читає CSV і повертає рядки потоком;
//   - 2-й аргумент (worker): для кожного рядка знаходить вузли (швидко завдяки
//     індексам з кроку 1) і створює ребро RATED з властивостями rating/timestamp.
// parallel:false — у worker ми покладаємось на MATCH існуючих вузлів; послідовне
// виконання безпечніше (нема конкурентних спроб створити/залочити ті самі вузли).
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM 'file:///ratings.csv' AS row RETURN row",
  "MATCH (u:User  {userId:  toInteger(row.userId)})
   MATCH (m:Movie {movieId: toInteger(row.movieId)})
   MERGE (u)-[r:RATED]->(m)
   SET r.rating    = toInteger(row.rating),
       r.timestamp = toInteger(row.timestamp)",
  {batchSize: 10000, parallel: false}
);


// ----------------------------------------------------------------------------
// 5. (ДОДАТКОВО) Індекс по властивості ребра RATED.rating
// ----------------------------------------------------------------------------
// Багато запитів фільтрують r.rating >= 4 / = 5. Relationship property index
// (Neo4j 5.x) допомагає планувальнику на таких фільтрах.
CREATE INDEX rated_rating IF NOT EXISTS FOR ()-[r:RATED]-() ON (r.rating);


// ----------------------------------------------------------------------------
// 6. ПЕРЕВІРКА РЕЗУЛЬТАТУ
// ----------------------------------------------------------------------------
MATCH (u:User)            RETURN count(u) AS users;     // очікуємо 6040
MATCH (m:Movie)           RETURN count(m) AS movies;    // очікуємо 3883
MATCH (g:Genre)           RETURN count(g) AS genres;    // очікуємо 18
MATCH ()-[r:RATED]->()    RETURN count(r) AS ratings;   // очікуємо 1000209
MATCH ()-[h:HAS_GENRE]->() RETURN count(h) AS hasGenre; // ~6408
