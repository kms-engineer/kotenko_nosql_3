// ----------------------------------------------------------------------------
// ЗАПИТ 1 (базовий).
// Усі фільми жанру «Thriller» із середнім рейтингом > 4.0.
// Йдемо від вузла-жанру Thriller (індекс по name) до його фільмів,
// потім збираємо всі оцінки кожного фільму й рахуємо середнє.
// numRatings залишаємо у виводі, щоб бачити, на скількох оцінках побудоване
// середнє (фільм з 3 оцінками 5.0 формально пройде поріг, але це шум).
// ----------------------------------------------------------------------------
MATCH (m:Movie)-[:HAS_GENRE]->(:Genre {name: 'Thriller'})
MATCH (m)<-[r:RATED]-()
WITH m, avg(r.rating) AS avgRating, count(r) AS numRatings
WHERE avgRating > 4.0
RETURN m.title AS title, round(avgRating, 2) AS avgRating, numRatings
ORDER BY avgRating DESC, numRatings DESC;


// ----------------------------------------------------------------------------
// ЗАПИТ 2 (базовий).
// Користувачі, які поставили оцінку «5» більш ніж 50 фільмам.
// Фільтруємо ребра rating = 5, групуємо по користувачу, рахуємо к-сть фільмів,
// лишаємо тих, у кого fives > 50.
// ----------------------------------------------------------------------------
MATCH (u:User)-[r:RATED]->(m:Movie)
WHERE r.rating = 5
WITH u, count(m) AS fives
WHERE fives > 50
RETURN u.userId AS userId, u.gender AS gender, u.age AS age,
       u.occupation AS occupation, fives
ORDER BY fives DESC;


// ----------------------------------------------------------------------------
// ЗАПИТ 3 (середній).
// Фільми, які ОБИДВА користувачі (userId=1 і userId=2) оцінили високо (>=4).
// Один патерн ловить обидва ребра до спільного фільму m — це і є сила графа:
// «спільний сусід» виражається однією лінією патерна.
// ----------------------------------------------------------------------------
MATCH (u1:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User {userId: 2})
WHERE r1.rating >= 4 AND r2.rating >= 4
RETURN m.title AS title, r1.rating AS user1Rating, r2.rating AS user2Rating
ORDER BY title;


// ----------------------------------------------------------------------------
// ЗАПИТ 4 (середній).
// Жанри, чиї фільми стабільно отримують високі оцінки: середній рейтинг
// і кількість оцінок по жанру. Сортуємо за середнім; numRatings показує,
// наскільки «масовий» жанр (стабільність = і високе середнє, і великий обсяг).
// ----------------------------------------------------------------------------
MATCH (g:Genre)<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-()
WITH g, avg(r.rating) AS avgRating, count(r) AS numRatings
RETURN g.name AS genre, round(avgRating, 3) AS avgRating, numRatings
ORDER BY avgRating DESC;


// ----------------------------------------------------------------------------
// ЗАПИТ 5 (складний) — колаборативна фільтрація.
// «Користувачі зі схожими смаками також дивилися».
// 1) збираємо всі фільми, які цільовий користувач уже бачив (seenMovies);
// 2) знаходимо «сусідів» — користувачів, що високо оцінили ті самі фільми,
//    і ранжуємо їх за кількістю спільних уподобань (overlap), беремо топ-50;
// 3) рекомендуємо фільми, які ці сусіди оцінили високо, а цільовий — ще НЕ бачив;
//    сортуємо за кількістю сусідів, що їх радять.
// Змінюй userId: 1 на потрібного користувача.
// ----------------------------------------------------------------------------
MATCH (target:User {userId: 1})-[:RATED]->(seen:Movie)
WITH target, collect(DISTINCT seen) AS seenMovies

MATCH (target)-[r1:RATED]->(shared:Movie)<-[r2:RATED]-(peer:User)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND peer <> target
WITH target, seenMovies, peer, count(shared) AS overlap
ORDER BY overlap DESC
LIMIT 50

MATCH (peer)-[r3:RATED]->(rec:Movie)
WHERE r3.rating >= 4 AND NOT rec IN seenMovies
WITH rec, count(DISTINCT peer) AS peers, avg(r3.rating) AS avgPeerRating
RETURN rec.title AS title, peers, round(avgPeerRating, 2) AS avgPeerRating
ORDER BY peers DESC, avgPeerRating DESC
LIMIT 10;


// ----------------------------------------------------------------------------
// ЗАПИТ 6 (складний) — найкоротший ланцюжок між двома користувачами.
// Шукаємо найкоротший шлях по ребрах RATED (без напрямку: U-M-U-M-...-U).
// Обмеження *..6 не дає піти у нескінченність; shortestPath бере найкоротший.
// length(p) — кількість ребер: 2 = спільний фільм, 4 = через посередника, тощо.
// ----------------------------------------------------------------------------
MATCH (u1:User {userId: 1}), (u2:User {userId: 5000})
MATCH p = shortestPath((u1)-[:RATED*..6]-(u2))
RETURN [n IN nodes(p) |
          CASE WHEN n:User  THEN 'User '  + toString(n.userId)
               WHEN n:Movie THEN 'Movie ' + n.title
          END] AS chain,
       length(p) AS pathLength;
