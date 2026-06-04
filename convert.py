# python3 convert.py
import csv
import os

SRC = "data/ml-1m"      # де лежать розпаковані .dat
DST = "import"          # звідки Neo4j читатиме CSV (примонтовано в контейнер)

os.makedirs(DST, exist_ok=True)


def convert(src_name, dst_name, header, ncols):
    """Конвертує один .dat-файл у .csv, беручи перші ncols полів кожного рядка."""
    src = os.path.join(SRC, src_name)
    dst = os.path.join(DST, dst_name)
    rows = 0
    with open(src, encoding="latin-1") as f_in, \
         open(dst, "w", newline="", encoding="utf-8") as f_out:
        writer = csv.writer(f_out)
        writer.writerow(header)
        for line in f_in:
            parts = line.rstrip("\n").split("::")
            writer.writerow(parts[:ncols])
            rows += 1
    print(f"{dst_name:14s} <- {src_name:12s}  ({rows} рядків)")


# movies.dat:  MovieID::Title::Genres
convert("movies.dat", "movies.csv", ["movieId", "title", "genres"], 3)

# users.dat:   UserID::Gender::Age::Occupation::Zip  (zip відкидаємо -> 4 поля)
convert("users.dat", "users.csv", ["userId", "gender", "age", "occupation"], 4)

# ratings.dat: UserID::MovieID::Rating::Timestamp
convert("ratings.dat", "ratings.csv", ["userId", "movieId", "rating", "timestamp"], 4)

print("Готово. CSV-файли у папці import/")
