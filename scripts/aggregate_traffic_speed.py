"""
ITS 국가교통정보센터 5분 단위 전국 링크 속도 데이터(zip)를 스트리밍으로 읽어
창원/진주 구간만 추려서 (도시, 링크ID, 요일구분, 시간대) 단위 평균속도로 집계한다.

입력: data/*.zip (내부에 YYYYMMDD_5Min.csv, 컬럼: CREATDE,CREATHM,LINKID,ROADINSTTCD,PASNGSPED,PASNGTIME)
출력: data/agg_link_speed_summary.csv
"""
import csv
import zipfile
from pathlib import Path

DATA_DIR = Path(r"C:\Users\user\Desktop\Development\project\changwon-bis\data")
OUT_PATH = DATA_DIR / "agg_link_speed_summary.csv"

CHANGWON_PREFIXES = {"414", "415", "416", "417", "418"}
JINJU_PREFIXES = {"381"}

# 2026-10-03(토,개천절) / 10-04(일) / 10-05~08(순수 평일) / 10-09(금,한글날)
DAY_TYPE = {
    "20261003": "SAT_HOLIDAY",
    "20261004": "SUN",
    "20261005": "WEEKDAY",
    "20261006": "WEEKDAY",
    "20261007": "WEEKDAY",
    "20261008": "WEEKDAY",
    "20261009": "FRI_HOLIDAY",
}


def time_bucket(hhmm: str) -> str:
    hour = int(hhmm[:2])
    if 7 <= hour < 9:
        return "COMMUTE_AM"
    if 9 <= hour < 17:
        return "DAYTIME"
    if 17 <= hour < 19:
        return "COMMUTE_PM"
    return "NIGHT"


def city_of(link_id: str) -> str | None:
    p3 = link_id[:3]
    if p3 in CHANGWON_PREFIXES:
        return "CHANGWON"
    if p3 in JINJU_PREFIXES:
        return "JINJU"
    return None


def main():
    # key: (city, link_id, day_type, bucket) -> [sum_speed, count]
    agg: dict[tuple, list[float]] = {}

    zip_files = sorted(DATA_DIR.glob("202610*_5Min.zip"))
    print(f"대상 파일 {len(zip_files)}개")

    for zf_path in zip_files:
        date_str = zf_path.stem.split("_")[0]
        day_type = DAY_TYPE.get(date_str)
        if day_type is None:
            print(f"  스킵(미매핑 날짜): {zf_path.name}")
            continue

        print(f"  처리 중: {zf_path.name} ({day_type})")
        row_count = 0
        matched = 0
        with zipfile.ZipFile(zf_path) as zf:
            inner_name = zf.namelist()[0]
            with zf.open(inner_name) as raw:
                import io

                text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
                reader = csv.reader(text)
                header = next(reader)
                for row in reader:
                    row_count += 1
                    link_id = row[2]
                    city = city_of(link_id)
                    if city is None:
                        continue
                    matched += 1
                    hhmm = row[1]
                    speed = row[4]
                    try:
                        speed_val = float(speed)
                    except ValueError:
                        continue
                    bucket = time_bucket(hhmm)
                    key = (city, link_id, day_type, bucket)
                    acc = agg.get(key)
                    if acc is None:
                        agg[key] = [speed_val, 1]
                    else:
                        acc[0] += speed_val
                        acc[1] += 1
        print(f"    전체 {row_count:,}행 중 창원/진주 매칭 {matched:,}행")

    print(f"집계 키 개수: {len(agg):,}")
    with open(OUT_PATH, "w", newline="", encoding="utf-8-sig") as out:
        writer = csv.writer(out)
        writer.writerow(["city", "link_id", "day_type", "time_bucket", "avg_speed_kmh", "sample_count"])
        for (city, link_id, day_type, bucket), (s, c) in sorted(agg.items()):
            writer.writerow([city, link_id, day_type, bucket, round(s / c, 2), c])

    print(f"완료: {OUT_PATH}")


if __name__ == "__main__":
    main()
