// ----------------------------------------------------------------------------
// Прискорення матеріалізації:
// один раз порахувати к-сть оцінок на кожен фільм і зберегти як властивість.
// Тоді фільтр популярності у 5.1 — це дешеве порівняння m.numRatings > 20,
// а не пере-обхід графа на кожній парі фільмів.
// ----------------------------------------------------------------------------
MATCH (m:Movie)<-[:RATED]-()
WITH m, count(*) AS c
SET m.numRatings = c;


// ----------------------------------------------------------------------------
// 5.1. PAGERANK НА ГРАФІ ФІЛЬМІВ
// ----------------------------------------------------------------------------

// Крок 1: матеріалізуємо ребра фільм–фільм через спільних користувачів,
// які ОБИДВА фільми оцінили високо (>=4). weight = к-сть таких користувачів.
// id(m1) < id(m2) — щоб кожну пару взяти один раз. Беремо лише популярні фільми
// (>20 оцінок) і топ-50000 найважчих ребер, щоб проєкція була керованою.
// Якщо крок виконується надто довго — підніми поріг до = 5 або зменш LIMIT.
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(m1) < id(m2)
  AND m1.numRatings > 20 AND m2.numRatings > 20
WITH m1, m2, count(u) AS weight
ORDER BY weight DESC
LIMIT 50000
MERGE (m1)-[co:CO_RATED]-(m2)
SET co.weight = weight;

// Крок 2: створюємо проєкцію на основі матеріалізованих ребер
CALL gds.graph.project(
  'movieGraph',
  'Movie',
  { CO_RATED: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: PageRank (зважений). Топ-20 фільмів за «авторитетністю» у графі смаків.
CALL gds.pageRank.stream('movieGraph', { relationshipWeightProperty: 'weight' })
YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS movie, score
RETURN movie.title AS title, movie.year AS year,
       movie.numRatings AS numRatings, round(score, 4) AS pageRank
ORDER BY score DESC
LIMIT 20;

// Крок 4: видаляємо проєкцію та тимчасові ребра
CALL gds.graph.drop('movieGraph');
MATCH ()-[co:CO_RATED]-() DELETE co;


// ----------------------------------------------------------------------------
// 5.2. ВИЯВЛЕННЯ СПІЛЬНОТ (LOUVAIN) НА ГРАФІ СХОЖОСТІ КОРИСТУВАЧІВ
// ----------------------------------------------------------------------------

// Крок 1: матеріалізуємо ребра користувач–користувач через спільні фільми,
// які обидва оцінили високо. weight = к-сть спільних уподобань.
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(u1) < id(u2)
  AND m.numRatings < 500   // виключаємо фільми-супервузли: спільна любов до
                           // блокбастера — слабкий сигнал смаку (як IDF), і саме
                           // вони підривали пам'ять транзакції (урок Частини 4)
WITH u1, u2, count(m) AS weight
ORDER BY weight DESC
LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

// Крок 2: створюємо проєкцію
CALL gds.graph.project(
  'userSimilarity',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: запускаємо Louvain і записуємо номер спільноти у властивість community.
// Повертає к-сть спільнот і modularity (якість розбиття).
CALL gds.louvain.write('userSimilarity', {
  relationshipWeightProperty: 'weight',
  writeProperty: 'community'
})
YIELD communityCount, modularity, modularities, ranLevels;

// Крок 4а: 10 найбільших спільнот за розміром.
MATCH (u:User)
WHERE u.community IS NOT NULL
RETURN u.community AS community, count(*) AS size
ORDER BY size DESC
LIMIT 10;

// Крок 4б: для 10 найбільших спільнот — 3 найпопулярніші жанри
// (за фільмами, які користувачі спільноти оцінили високо).
MATCH (u:User)
WHERE u.community IS NOT NULL
WITH u.community AS community, count(*) AS size
ORDER BY size DESC
LIMIT 10
MATCH (u:User {community: community})-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE r.rating >= 4
WITH community, size, g.name AS genre, count(*) AS cnt
ORDER BY community, cnt DESC
WITH community, size, collect(genre)[0..3] AS topGenres
RETURN community, size, topGenres
ORDER BY size DESC;

// Крок 5: видаляємо проєкцію
CALL gds.graph.drop('userSimilarity');


// ----------------------------------------------------------------------------
// 5.3. НАЙКОРОТШИЙ ШЛЯХ МІЖ КОРИСТУВАЧАМИ (DIJKSTRA)
// ----------------------------------------------------------------------------

// Якщо ребра SIMILAR уже видалені — перестворюємо (інакше пропусти цей блок):
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(u1) < id(u2)
  AND m.numRatings < 500   // виключаємо фільми-супервузли: спільна любов до
                           // блокбастера — слабкий сигнал смаку (як IDF), і саме
                           // вони підривали пам'ять транзакції (урок Частини 4)
WITH u1, u2, count(m) AS weight
ORDER BY weight DESC
LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

// Проєкція для Dijkstra
CALL gds.graph.project(
  'userGraph',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Dijkstra між обраною парою користувачів.
// УВАГА про сенс ваги: weight = к-сть спільних фільмів (більше = ближче «по смаку»),
// а Dijkstra мінімізує СУМУ ваг (менше = коротше). Тобто прямий запуск шукає шлях
// з найменшою сумарною вагою. Нижче — базовий варіант (як у завданні); у README
// наведено й варіант з інвертованою вагою 1.0/weight для семантики «схожості».
// УВАГА: бери userId, що реально у зв'язному компоненті SIMILAR (інакше порожньо!).
// Користувачі 1 і 2 — ізольовані (шляху нема). Робочі пари: (17,62), (18,48), (19,33).
// Знайти кандидатів: MATCH (u:User) WHERE u.community IS NOT NULL
//   WITH u.community AS c, collect(u.userId) AS m, count(*) AS sz ORDER BY sz DESC
//   LIMIT 1 RETURN m[0..6];
MATCH (source:User {userId: 17}), (target:User {userId: 62})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'weight'
})
YIELD totalCost, nodeIds, costs
RETURN totalCost,
       size(nodeIds) - 1 AS hops,
       [id IN nodeIds | gds.util.asNode(id).userId] AS userPath,
       costs;

// Крок прибирання
CALL gds.graph.drop('userGraph');
MATCH ()-[sim:SIMILAR]-() DELETE sim;
